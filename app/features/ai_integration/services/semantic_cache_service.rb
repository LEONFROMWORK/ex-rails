# frozen_string_literal: true

module AiIntegration
  module Services
    # 의미론적 유사성 기반 캐시 서비스 - 유사한 쿼리의 응답을 재사용
    class SemanticCacheService
      SIMILARITY_THRESHOLD = 0.85  # 캐시 히트로 간주할 유사도 임계값
      CACHE_TTL = 24.hours
      MAX_CACHE_SIZE = 10_000

      def initialize
        @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
        @embedding_service = EmbeddingService.new
        @monitoring = QualityMonitoringService.instance
      end

      # 캐시 조회
      def get(query, context = {})
        return nil if should_skip_cache?(query, context)

        start_time = Time.current

        # 쿼리 임베딩 생성
        query_embedding = generate_embedding(query)

        # 유사한 캐시 항목 검색
        similar_entries = find_similar_entries(query_embedding)

        if similar_entries.any?
          best_match = similar_entries.first

          # 유사도가 임계값 이상인 경우만 사용
          if best_match[:similarity] >= SIMILARITY_THRESHOLD
            # 캐시 히트 기록
            @monitoring.record_metric(:cache_hit_rate, 1,
                                    similarity: best_match[:similarity])

            Rails.logger.info("Semantic cache hit: similarity=#{best_match[:similarity]}")

            # 캐시된 응답 반환
            cached_response = JSON.parse(best_match[:response])
            cached_response["from_cache"] = true
            cached_response["cache_similarity"] = best_match[:similarity]
            cached_response["original_query"] = best_match[:original_query]

            return cached_response
          end
        end

        # 캐시 미스 기록
        @monitoring.record_metric(:cache_hit_rate, 0)
        nil

      rescue StandardError => e
        Rails.logger.error("Semantic cache lookup failed: #{e.message}")
        nil
      end

      # 캐시 저장
      def set(query, response, context = {})
        return if should_skip_cache?(query, context)
        return unless cacheable_response?(response)

        begin
          # 쿼리 임베딩 생성
          query_embedding = generate_embedding(query)

          # 캐시 엔트리 생성
          cache_entry = {
            query: query,
            query_embedding: query_embedding,
            response: response.to_json,
            context: sanitize_context(context),
            timestamp: Time.current.to_f,
            model: response[:model_used],
            tier: response[:tier_used],
            confidence: response[:confidence_score]
          }

          # Redis에 저장
          store_cache_entry(cache_entry)

          # 캐시 크기 관리
          manage_cache_size

          Rails.logger.info("Stored in semantic cache: query_length=#{query.length}")

        rescue StandardError => e
          Rails.logger.error("Semantic cache storage failed: #{e.message}")
        end
      end

      # 캐시 무효화
      def invalidate(pattern = nil)
        if pattern
          # 패턴 매칭으로 특정 캐시 항목 삭제
          invalidate_by_pattern(pattern)
        else
          # 전체 캐시 삭제
          invalidate_all
        end
      end

      # 캐시 통계
      def stats
        {
          total_entries: @redis.zcard("semantic_cache:embeddings"),
          memory_usage: calculate_memory_usage,
          oldest_entry: get_oldest_entry_age,
          hit_rate: calculate_hit_rate,
          top_queries: get_top_cached_queries
        }
      end

      # 유사 쿼리 클러스터링
      def find_query_clusters(min_cluster_size: 3)
        all_embeddings = get_all_embeddings

        # DBSCAN 또는 간단한 클러스터링 알고리즘 사용
        clusters = simple_clustering(all_embeddings, min_cluster_size)

        # 클러스터별 대표 쿼리 추출
        clusters.map do |cluster|
          {
            size: cluster.size,
            representative_query: cluster.first[:query],
            common_patterns: extract_common_patterns(cluster),
            avg_confidence: cluster.sum { |e| e[:confidence] } / cluster.size
          }
        end
      end

      private

      def should_skip_cache?(query, context)
        # 캐시를 건너뛰어야 하는 경우
        return true if context[:skip_cache]
        return true if context[:force_fresh]
        return true if query.length < 10  # 너무 짧은 쿼리
        return true if contains_personal_info?(query)

        false
      end

      def cacheable_response?(response)
        # 캐시 가능한 응답인지 확인
        return false unless response[:success]
        return false if response[:confidence_score] < 0.7
        return false if response[:error].present?

        true
      end

      def generate_embedding(text)
        result = @embedding_service.call(text)

        if result.success?
          result.value
        else
          Rails.logger.error("Embedding generation failed: #{result.error}")
          nil
        end
      end

      def find_similar_entries(query_embedding)
        return [] unless query_embedding

        # pgvector를 사용한 유사도 검색 (Redis 대신 PostgreSQL 사용도 가능)
        all_entries = get_all_cache_entries

        # 코사인 유사도 계산
        similarities = all_entries.map do |entry|
          embedding = JSON.parse(entry[:embedding])
          similarity = cosine_similarity(query_embedding, embedding)

          {
            key: entry[:key],
            similarity: similarity,
            response: entry[:response],
            original_query: entry[:query],
            timestamp: entry[:timestamp]
          }
        end

        # 유사도 순으로 정렬
        similarities.sort_by { |s| -s[:similarity] }.take(5)
      end

      def cosine_similarity(vec1, vec2)
        return 0 unless vec1 && vec2 && vec1.size == vec2.size

        dot_product = vec1.zip(vec2).sum { |a, b| a * b }
        magnitude1 = Math.sqrt(vec1.sum { |a| a * a })
        magnitude2 = Math.sqrt(vec2.sum { |a| a * a })

        return 0 if magnitude1 == 0 || magnitude2 == 0

        dot_product / (magnitude1 * magnitude2)
      end

      def store_cache_entry(entry)
        key = "semantic_cache:#{SecureRandom.hex(16)}"

        # 메타데이터 저장
        @redis.hset(key, {
          query: entry[:query],
          response: entry[:response],
          context: entry[:context].to_json,
          model: entry[:model],
          tier: entry[:tier],
          confidence: entry[:confidence],
          timestamp: entry[:timestamp]
        })

        # 임베딩을 별도로 저장 (검색용)
        @redis.zadd("semantic_cache:embeddings", entry[:timestamp], key)
        @redis.hset("embeddings:#{key}", "data", entry[:query_embedding].to_json)

        # TTL 설정
        @redis.expire(key, CACHE_TTL)
        @redis.expire("embeddings:#{key}", CACHE_TTL)
      end

      def get_all_cache_entries
        keys = @redis.zrange("semantic_cache:embeddings", 0, -1)

        keys.map do |key|
          data = @redis.hgetall(key)
          embedding_data = @redis.hget("embeddings:#{key}", "data")

          next unless data.any? && embedding_data

          {
            key: key,
            query: data["query"],
            response: data["response"],
            embedding: embedding_data,
            timestamp: data["timestamp"].to_f,
            confidence: data["confidence"].to_f
          }
        end.compact
      end

      def manage_cache_size
        current_size = @redis.zcard("semantic_cache:embeddings")

        if current_size > MAX_CACHE_SIZE
          # 가장 오래된 항목들 제거
          to_remove = current_size - MAX_CACHE_SIZE
          oldest_keys = @redis.zrange("semantic_cache:embeddings", 0, to_remove - 1)

          oldest_keys.each do |key|
            @redis.del(key)
            @redis.del("embeddings:#{key}")
          end

          @redis.zremrangebyrank("semantic_cache:embeddings", 0, to_remove - 1)

          Rails.logger.info("Removed #{to_remove} old cache entries")
        end
      end

      def sanitize_context(context)
        # 개인정보나 민감한 정보 제거
        context.except(:user_id, :api_key, :session_id)
      end

      def contains_personal_info?(text)
        # 간단한 개인정보 패턴 검사
        patterns = [
          /\b\d{3}-\d{2}-\d{4}\b/,  # SSN
          /\b\d{6}-\d{7}\b/,         # 주민번호
          /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, # 이메일
          /\b\d{3,4}-\d{3,4}-\d{4}\b/ # 전화번호
        ]

        patterns.any? { |pattern| text.match?(pattern) }
      end

      def simple_clustering(entries, min_size)
        # 간단한 밀도 기반 클러스터링
        clusters = []
        visited = Set.new

        entries.each_with_index do |entry, i|
          next if visited.include?(i)

          cluster = [ entry ]
          visited.add(i)

          # 이웃 찾기
          entries.each_with_index do |other, j|
            next if i == j || visited.include?(j)

            similarity = cosine_similarity(
              JSON.parse(entry[:embedding]),
              JSON.parse(other[:embedding])
            )

            if similarity > 0.9  # 매우 유사한 것만 같은 클러스터로
              cluster << other
              visited.add(j)
            end
          end

          clusters << cluster if cluster.size >= min_size
        end

        clusters
      end

      def extract_common_patterns(cluster)
        queries = cluster.map { |e| e[:query].downcase.split(/\s+/) }

        # 공통 단어 찾기
        common_words = queries.reduce(&:&)

        # 공통 패턴 추출
        patterns = []
        patterns << "공통 키워드: #{common_words.join(', ')}" if common_words.any?
        patterns << "평균 길이: #{queries.map(&:size).sum / queries.size}단어"

        patterns
      end

      def calculate_hit_rate
        # 최근 1시간 히트율 계산
        hits = @redis.get("cache_hits:hour").to_i
        misses = @redis.get("cache_misses:hour").to_i
        total = hits + misses

        return 0 if total == 0

        (hits.to_f / total * 100).round(2)
      end

      def get_top_cached_queries(limit = 10)
        entries = get_all_cache_entries

        # 신뢰도가 높은 상위 쿼리들
        entries.sort_by { |e| -e[:confidence] }
               .take(limit)
               .map do |e|
                 {
                   query: e[:query],
                   confidence: e[:confidence],
                   age_hours: (Time.current - Time.at(e[:timestamp])) / 3600.0
                 }
               end
      end

      def calculate_memory_usage
        # Redis 메모리 사용량 추정
        total_size = 0

        keys = @redis.zrange("semantic_cache:embeddings", 0, -1)
        keys.each do |key|
          # 각 키의 메모리 사용량 추정
          data = @redis.hgetall(key)
          total_size += data.to_s.bytesize

          embedding_data = @redis.hget("embeddings:#{key}", "data")
          total_size += embedding_data.to_s.bytesize if embedding_data
        end

        # MB 단위로 변환
        (total_size / 1024.0 / 1024.0).round(2)
      end

      def get_oldest_entry_age
        oldest_timestamp = @redis.zrange("semantic_cache:embeddings", 0, 0, with_scores: true).first&.last

        return nil unless oldest_timestamp

        (Time.current - Time.at(oldest_timestamp)) / 3600.0  # 시간 단위
      end
    end
  end
end
