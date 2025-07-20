# frozen_string_literal: true

module AiIntegration
  module Services
    # 쿼리 복잡도를 분석하여 적절한 모델 티어를 추천
    class QueryComplexityAnalyzer
      # 복잡도 점수 범위
      COMPLEXITY_LEVELS = {
        simple: 0..30,
        moderate: 31..70,
        complex: 71..100
      }.freeze

      # 티어 매핑
      TIER_MAPPING = {
        simple: :cost_effective,
        moderate: :balanced,
        complex: :premium
      }.freeze

      def initialize
        @cache = Rails.cache
      end

      # 쿼리 복잡도 분석 및 추천 티어 반환
      def analyze(query, context = {})
        # 캐시 확인
        cache_key = "query_complexity:#{Digest::SHA256.hexdigest(query)}"
        cached = @cache.read(cache_key)
        return cached if cached

        # 복잡도 점수 계산
        complexity_score = calculate_complexity_score(query, context)

        # 복잡도 레벨 결정
        complexity_level = determine_complexity_level(complexity_score)

        # 추천 티어 결정
        recommended_tier = TIER_MAPPING[complexity_level]

        # 컨텍스트 기반 조정
        adjusted_tier = adjust_tier_by_context(recommended_tier, context)

        result = {
          query: query,
          complexity_score: complexity_score,
          complexity_level: complexity_level,
          recommended_tier: adjusted_tier,
          analysis_details: {
            linguistic_complexity: analyze_linguistic_complexity(query),
            domain_complexity: analyze_domain_complexity(query),
            computational_complexity: analyze_computational_complexity(query),
            context_factors: analyze_context_factors(context)
          },
          reasoning: generate_reasoning(complexity_score, complexity_level, adjusted_tier)
        }

        # 캐시 저장
        @cache.write(cache_key, result, expires_in: 1.hour)

        result
      end

      # 배치 분석
      def analyze_batch(queries)
        queries.map { |query| analyze(query) }
      end

      private

      def calculate_complexity_score(query, context)
        scores = []

        # 1. 언어적 복잡도 (30%)
        linguistic_score = analyze_linguistic_complexity(query)
        scores << linguistic_score * 0.3

        # 2. 도메인 복잡도 (30%)
        domain_score = analyze_domain_complexity(query)
        scores << domain_score * 0.3

        # 3. 계산적 복잡도 (25%)
        computational_score = analyze_computational_complexity(query)
        scores << computational_score * 0.25

        # 4. 컨텍스트 요인 (15%)
        context_score = analyze_context_factors(context)
        scores << context_score * 0.15

        # 총점 계산
        total_score = scores.sum.round
        [ total_score, 100 ].min
      end

      def analyze_linguistic_complexity(query)
        score = 0

        # 쿼리 길이
        word_count = query.split(/\s+/).length
        score += case word_count
        when 1..5 then 10
        when 6..15 then 20
        when 16..30 then 40
        when 31..50 then 60
        else 80
        end

        # 문장 복잡도
        sentences = query.split(/[.!?]+/)
        if sentences.length > 3
          score += 20
        elsif sentences.length > 1
          score += 10
        end

        # 조건문/논리 연산자
        logical_operators = /\b(if|when|unless|and|or|but|however|although|whereas)\b/i
        score += 15 if query.match?(logical_operators)

        # 비교/대조 표현
        comparison_terms = /\b(compare|contrast|versus|vs|better|worse|more|less|than)\b/i
        score += 15 if query.match?(comparison_terms)

        # 복잡한 질문 유형
        complex_questions = /\b(how|why|explain|analyze|evaluate|assess)\b/i
        score += 20 if query.match?(complex_questions)

        [ score, 100 ].min
      end

      def analyze_domain_complexity(query)
        score = 0

        # Excel 고급 기능
        advanced_features = {
          pivot: 30,
          'array formula': 40,
          'vba|macro': 50,
          'power query': 45,
          'data model': 40,
          'cube function': 50,
          'solver': 35
        }

        advanced_features.each do |feature, points|
          score += points if query.match?(/\b#{feature}\b/i)
        end

        # 복잡한 함수들
        complex_functions = %w[
          XLOOKUP FILTER SEQUENCE LAMBDA LET
          SUMIFS COUNTIFS INDEX.*MATCH
          INDIRECT OFFSET GETPIVOTDATA
        ]

        complex_functions.each do |func|
          score += 25 if query.match?(/\b#{func}\b/i)
        end

        # 통계/분석 용어
        statistical_terms = /\b(regression|correlation|variance|deviation|forecast|trend)\b/i
        score += 30 if query.match?(statistical_terms)

        # 대용량 데이터 처리
        large_data_terms = /\b(million|thousands?|large\s+dataset|performance|optimize)\b/i
        score += 20 if query.match?(large_data_terms)

        [ score, 100 ].min
      end

      def analyze_computational_complexity(query)
        score = 0

        # 다중 단계 처리
        multi_step_indicators = /\b(then|after|next|step|finally|afterwards)\b/i
        score += 25 if query.scan(multi_step_indicators).length > 2

        # 중첩된 조건
        nested_conditions = /\b(if.*if|when.*when)\b/i
        score += 30 if query.match?(nested_conditions)

        # 복잡한 계산
        calculation_terms = /\b(calculate|compute|derive|formula|equation)\b/i
        score += 20 if query.match?(calculation_terms)

        # 데이터 변환/조작
        transformation_terms = /\b(transform|convert|reshape|pivot|unpivot|normalize)\b/i
        score += 25 if query.match?(transformation_terms)

        # 에러 처리/디버깅
        error_terms = /\b(error|debug|troubleshoot|fix|issue|problem)\b/i
        score += 20 if query.match?(error_terms)

        [ score, 100 ].min
      end

      def analyze_context_factors(context)
        score = 0

        # 이미지 분석 요청
        score += 30 if context[:has_image]

        # 이전 시도 실패
        score += 20 if context[:previous_failures]&.positive?

        # 긴급/중요 표시
        score += 25 if context[:priority] == "high"

        # 전문가 모드
        score += 20 if context[:expert_mode]

        # 대화 히스토리가 긴 경우
        if context[:conversation_length]
          score += case context[:conversation_length]
          when 0..3 then 0
          when 4..6 then 10
          when 7..10 then 20
          else 30
          end
        end

        [ score, 100 ].min
      end

      def determine_complexity_level(score)
        COMPLEXITY_LEVELS.find { |_level, range| range.include?(score) }&.first || :moderate
      end

      def adjust_tier_by_context(base_tier, context)
        # 강제 티어 설정
        return context[:force_tier] if context[:force_tier]

        # 비용 최적화 모드
        if context[:cost_optimization] && base_tier != :cost_effective
          return downgrade_tier(base_tier)
        end

        # 품질 우선 모드
        if context[:quality_first] && base_tier != :premium
          return upgrade_tier(base_tier)
        end

        # 이미지가 있으면 최소 balanced
        if context[:has_image] && base_tier == :cost_effective
          return :balanced
        end

        base_tier
      end

      def upgrade_tier(tier)
        case tier
        when :cost_effective then :balanced
        when :balanced then :premium
        else tier
        end
      end

      def downgrade_tier(tier)
        case tier
        when :premium then :balanced
        when :balanced then :cost_effective
        else tier
        end
      end

      def generate_reasoning(score, level, tier)
        reasons = []

        reasons << "복잡도 점수: #{score}/100"
        reasons << "복잡도 수준: #{level}"
        reasons << "추천 티어: #{tier}"

        if score > 70
          reasons << "고급 Excel 기능이나 복잡한 분석이 필요한 쿼리입니다."
        elsif score > 30
          reasons << "중간 수준의 복잡도로 균형잡힌 모델이 적합합니다."
        else
          reasons << "간단한 쿼리로 비용 효율적인 모델로 충분합니다."
        end

        reasons.join(" ")
      end
    end
  end
end
