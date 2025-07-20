# frozen_string_literal: true

module AiIntegration
  module Services
    # 고급 캐싱 전략: 컨텍스트 인식, 프리페칭, 적응형 TTL
    class AdvancedCacheService < SemanticCacheService
      # 캐시 전략 설정
      CACHE_STRATEGIES = {
        context_aware: true,
        prefetching: true,
        adaptive_ttl: true,
        compression: true,
        distributed: true
      }.freeze

      # 프리페칭 규칙
      PREFETCH_RULES = {
        sequential_queries: {
          pattern: /step (\d+)/i,
          prefetch: :next_steps
        },
        related_functions: {
          pattern: /VLOOKUP|INDEX.*MATCH/i,
          prefetch: :related_excel_functions
        },
        error_solutions: {
          pattern: /#REF|#VALUE|#NAME/i,
          prefetch: :common_error_fixes
        }
      }.freeze

      def initialize
        super
        @prefetch_queue = Queue.new
        @context_store = {}
        @ttl_optimizer = TtlOptimizer.new
        start_prefetch_worker
      end

      # 컨텍스트 인식 캐시 조회
      def get_with_context(query, context = {})
        # 기본 캐시 조회
        base_result = get(query, context)

        # 컨텍스트 기반 향상
        if base_result && context[:conversation_id]
          enhance_with_conversation_context(base_result, context[:conversation_id])
        elsif !base_result && context[:user_id]
          # 사용자별 유사 쿼리 확인
          user_specific_result = find_user_specific_cache(query, context[:user_id])
          return user_specific_result if user_specific_result
        end

        # 프리페칭 트리거
        trigger_prefetching(query, context) if CACHE_STRATEGIES[:prefetching]

        base_result
      end

      # 컨텍스트 인식 캐시 저장
      def set_with_context(query, response, context = {})
        # 적응형 TTL 계산
        ttl = calculate_adaptive_ttl(response, context)

        # 압축 여부 결정
        compressed_response = should_compress?(response) ? compress_response(response) : response

        # 컨텍스트 메타데이터 추가
        enhanced_entry = {
          query: query,
          response: compressed_response,
          context: extract_relevant_context(context),
          ttl: ttl,
          created_at: Time.current,
          access_pattern: initialize_access_pattern
        }

        # 기본 캐시 저장
        set(query, compressed_response, context)

        # 컨텍스트 인덱스 업데이트
        update_context_indices(query, enhanced_entry, context)

        # 관련 쿼리 프리페칭
        schedule_related_prefetches(query, response, context)
      end

      # 프리페칭 실행
      def prefetch(queries, context = {})
        queries.each do |query|
          @prefetch_queue << { query: query, context: context, priority: calculate_prefetch_priority(query) }
        end
      end

      # 대화 컨텍스트 기반 캐시
      def get_conversation_cache(conversation_id, limit = 10)
        cache_keys = @redis.zrevrange("conversation_cache:#{conversation_id}", 0, limit - 1)

        cache_keys.map do |key|
          data = @redis.hgetall(key)
          next unless data.any?

          {
            query: data["query"],
            response: decompress_if_needed(data["response"]),
            timestamp: data["timestamp"].to_f,
            relevance: calculate_conversation_relevance(data, conversation_id)
          }
        end.compact
      end

      # 접근 패턴 분석
      def analyze_access_patterns
        patterns = {}

        # 시간대별 접근 패턴
        patterns[:temporal] = analyze_temporal_access

        # 쿼리 시퀀스 패턴
        patterns[:sequences] = analyze_query_sequences

        # 사용자별 패턴
        patterns[:user_patterns] = analyze_user_patterns

        # 프리페칭 효과성
        patterns[:prefetch_effectiveness] = calculate_prefetch_metrics

        patterns
      end

      # 캐시 워밍
      def warm_cache(strategy: :popular)
        case strategy
        when :popular
          warm_popular_queries
        when :predicted
          warm_predicted_queries
        when :scheduled
          warm_scheduled_queries
        end
      end

      private

      def calculate_adaptive_ttl(response, context)
        base_ttl = CACHE_TTL

        # 품질 기반 조정
        quality_multiplier = response[:confidence_score] || 0.7

        # 변경 빈도 기반 조정
        volatility = estimate_content_volatility(response[:analysis])
        volatility_multiplier = 1.0 - (volatility * 0.5)

        # 접근 빈도 예측
        access_frequency = predict_access_frequency(response[:query])
        frequency_multiplier = access_frequency > 0.1 ? 1.5 : 1.0

        # 비용 기반 조정
        cost_multiplier = response[:cost_breakdown][:current_cost] > 0.01 ? 2.0 : 1.0

        # 최종 TTL 계산
        ttl = base_ttl * quality_multiplier * volatility_multiplier * frequency_multiplier * cost_multiplier

        # 범위 제한
        [ ttl, 7.days ].min
      end

      def should_compress?(response)
        # 크기 기반 압축 결정
        response.to_json.bytesize > 1.kilobyte
      end

      def compress_response(response)
        json_data = response.to_json
        compressed = Zlib::Deflate.deflate(json_data)

        {
          compressed: true,
          data: Base64.encode64(compressed),
          original_size: json_data.bytesize,
          compressed_size: compressed.bytesize
        }
      end

      def decompress_if_needed(data)
        return data unless data.is_a?(String)

        parsed = JSON.parse(data) rescue data

        if parsed.is_a?(Hash) && parsed["compressed"]
          compressed_data = Base64.decode64(parsed["data"])
          decompressed = Zlib::Inflate.inflate(compressed_data)
          JSON.parse(decompressed)
        else
          parsed
        end
      end

      def trigger_prefetching(query, context)
        # 프리페치 규칙 확인
        PREFETCH_RULES.each do |rule_name, rule|
          if query.match?(rule[:pattern])
            queries_to_prefetch = generate_prefetch_queries(query, rule[:prefetch])
            prefetch(queries_to_prefetch, context)
          end
        end

        # 시퀀스 기반 프리페칭
        if context[:conversation_id]
          next_likely_queries = predict_next_queries(query, context[:conversation_id])
          prefetch(next_likely_queries, context) if next_likely_queries.any?
        end
      end

      def generate_prefetch_queries(original_query, prefetch_type)
        case prefetch_type
        when :next_steps
          # 다음 단계 쿼리 생성
          if match = original_query.match(/step (\d+)/i)
            current_step = match[1].to_i
            (1..3).map { |i| original_query.gsub(/step \d+/i, "step #{current_step + i}") }
          else
            []
          end

        when :related_excel_functions
          # 관련 Excel 함수 쿼리
          functions = %w[VLOOKUP HLOOKUP INDEX MATCH XLOOKUP]
          functions.map { |func| "How to use #{func} function in Excel" }

        when :common_error_fixes
          # 일반적인 오류 해결 방법
          [
            "How to fix #REF error in Excel",
            "How to fix #VALUE error in Excel",
            "How to fix #NAME error in Excel",
            "Common Excel formula errors and solutions"
          ]
        else
          []
        end
      end

      def predict_next_queries(current_query, conversation_id)
        # 대화 히스토리에서 패턴 학습
        history = get_conversation_history(conversation_id)

        # 마르코프 체인 기반 예측
        query_sequences = extract_query_sequences(history)
        predictions = []

        query_sequences.each do |sequence|
          current_index = sequence.index { |q| similar_query?(q, current_query) }

          if current_index && current_index < sequence.length - 1
            predictions << sequence[current_index + 1]
          end
        end

        # 빈도 기반 상위 예측 반환
        predictions.group_by(&:itself)
                  .sort_by { |_, instances| -instances.length }
                  .take(3)
                  .map(&:first)
      end

      def start_prefetch_worker
        Thread.new do
          loop do
            begin
              # 우선순위 큐에서 프리페치 작업 가져오기
              task = @prefetch_queue.pop

              # 이미 캐시되어 있는지 확인
              next if get(task[:query], task[:context])

              # 프리페치 실행
              execute_prefetch(task)

              # 과부하 방지
              sleep(0.1)

            rescue StandardError => e
              Rails.logger.error("Prefetch worker error: #{e.message}")
            end
          end
        end
      end

      def execute_prefetch(task)
        # 실제 API 호출 대신 시뮬레이션 또는 경량 버전 사용
        Rails.logger.info("Prefetching: #{task[:query]}")

        # 낮은 우선순위로 실행
        Thread.current.priority = -1

        # 실제 서비스 호출 (가능한 경우)
        # 여기서는 캐시 워밍만 수행
      end

      def enhance_with_conversation_context(result, conversation_id)
        # 대화 맥락에서 추가 정보 추출
        recent_context = get_recent_conversation_context(conversation_id)

        if recent_context[:topics].any?
          result["contextual_hints"] = generate_contextual_hints(result, recent_context[:topics])
        end

        if recent_context[:user_level]
          result["explanation_level"] = adjust_explanation_level(result, recent_context[:user_level])
        end

        result
      end

      def update_context_indices(query, entry, context)
        # 사용자별 인덱스
        if context[:user_id]
          @redis.zadd("user_cache:#{context[:user_id]}", Time.current.to_f, entry_key(entry))
        end

        # 대화별 인덱스
        if context[:conversation_id]
          @redis.zadd("conversation_cache:#{context[:conversation_id]}", Time.current.to_f, entry_key(entry))
        end

        # 주제별 인덱스
        topics = extract_topics(query)
        topics.each do |topic|
          @redis.zadd("topic_cache:#{topic}", entry[:created_at].to_f, entry_key(entry))
        end

        # 시간대별 인덱스
        hour_key = Time.current.strftime("%Y%m%d%H")
        @redis.zadd("hourly_cache:#{hour_key}", entry[:created_at].to_f, entry_key(entry))
      end

      def warm_popular_queries
        # 인기 쿼리 상위 N개 캐시
        popular_queries = @redis.zrevrange("query_popularity", 0, 49)

        popular_queries.each do |query|
          next if get(query)

          # 백그라운드에서 캐시 워밍
          WarmCacheJob.perform_later(query)
        end
      end

      def warm_predicted_queries
        # 시간대별 예측 쿼리 캐시
        hour = Time.current.hour
        predicted_queries = @redis.smembers("predicted_queries:hour_#{hour}")

        predicted_queries.each do |query|
          prefetch([ query ], { warming: true })
        end
      end

      def estimate_content_volatility(content)
        # 콘텐츠 변경 가능성 추정
        volatility_indicators = {
          date_references: content.scan(/\d{4}-\d{2}-\d{2}/).count,
          version_numbers: content.scan(/v?\d+\.\d+/).count,
          temporary_words: content.scan(/\b(temporary|current|today|now)\b/i).count
        }

        # 0-1 범위로 정규화
        total_indicators = volatility_indicators.values.sum
        [ total_indicators / 10.0, 1.0 ].min
      end

      def predict_access_frequency(query)
        # 과거 접근 패턴 기반 빈도 예측
        similar_queries = find_similar_historical_queries(query)

        return 0.05 if similar_queries.empty?

        # 평균 일일 접근 횟수
        total_accesses = similar_queries.sum { |q| q[:access_count] }
        days_span = (Time.current - similar_queries.first[:first_seen]).to_f / 1.day

        return 0.1 if days_span == 0

        (total_accesses / days_span / 100.0).round(3) # 정규화
      end

      def calculate_prefetch_metrics
        hits = @redis.get("prefetch:hits").to_i
        total = @redis.get("prefetch:total").to_i

        return { hit_rate: 0, saved_time: 0 } if total == 0

        {
          hit_rate: (hits.to_f / total * 100).round(2),
          saved_time: @redis.get("prefetch:time_saved").to_f,
          queries_prefetched: total
        }
      end

      # TTL 최적화 내부 클래스
      class TtlOptimizer
        def initialize
          @access_history = {}
        end

        def optimize_ttl(key, current_ttl, access_count)
          # 접근 빈도에 따른 TTL 조정
          if access_count > 10
            current_ttl * 1.5
          elsif access_count < 2
            current_ttl * 0.7
          else
            current_ttl
          end
        end
      end
    end
  end
end
