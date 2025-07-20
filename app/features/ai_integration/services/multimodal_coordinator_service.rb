# frozen_string_literal: true

module AiIntegration
  module Services
    # 멀티모달 분석을 조정하고 품질 기반 폴백을 관리하는 서비스
    class MultimodalCoordinatorService
      attr_reader :user, :default_tier, :quality_threshold

      def initialize(user:, default_tier: :cost_effective, quality_threshold: 0.65)
        @user = user
        @default_tier = default_tier
        @quality_threshold = quality_threshold
        @cache = Rails.cache
        @complexity_analyzer = QueryComplexityAnalyzer.new
        @advanced_cache = AdvancedCacheService.new
        @ab_testing = AbTestingService.instance
        @auto_tuning = AutoTuningService.instance
      end

      # 이미지 분석 요청 처리
      def analyze_image(image_data:, prompt:, options: {})
        # 자동 튜닝된 파라미터 가져오기
        tuned_params = @auto_tuning.get_optimized_parameters(
          user_id: @user.id,
          query_type: "multimodal",
          current_hour: Time.current.hour
        )

        # A/B 테스트 파라미터 적용
        @quality_threshold = @ab_testing.get_variant(
          user_id: @user.id,
          parameter: :quality_threshold
        )

        # 고급 캐시 확인 (컨텍스트 인식)
        context = {
          user_id: @user.id,
          conversation_id: options[:conversation_id],
          has_image: true
        }

        cached = @advanced_cache.get_with_context(prompt, context)
        if cached && options[:use_cache] != false
          # A/B 테스트 결과 추적
          @ab_testing.track_outcome(
            user_id: @user.id,
            parameter: :quality_threshold,
            outcome: {
              success: true,
              cache_hit: true,
              quality_score: cached[:confidence_score]
            }
          )
          return cached
        end

        # 분석 수행
        result = perform_analysis(
          image_data: image_data,
          prompt: prompt,
          options: options
        )

        # 고급 캐시에 저장 (컨텍스트 포함)
        if result[:success] && result[:confidence_score] >= @quality_threshold
          @advanced_cache.set_with_context(prompt, result, context)
        end

        # A/B 테스트 결과 추적
        @ab_testing.track_outcome(
          user_id: @user.id,
          parameter: :quality_threshold,
          outcome: {
            success: result[:success],
            cache_hit: false,
            quality_score: result[:confidence_score],
            response_time: result[:processing_time],
            cost: result[:cost_info][:estimated_cost]
          }
        )

        # 이상 탐지 및 자동 조정
        @auto_tuning.detect_and_adjust_anomalies

        result
      end

      # Excel 스크린샷 특화 분석
      def analyze_excel_screenshot(image_data:, context: {})
        prompt = build_excel_analysis_prompt(context)

        analyze_image(
          image_data: image_data,
          prompt: prompt,
          options: {
            min_confidence: 0.7,  # Excel 분석은 높은 품질 요구
            analysis_type: "excel_screenshot",
            context: context
          }
        )
      end

      # 차트/그래프 특화 분석
      def analyze_chart(image_data:, chart_type: nil)
        prompt = build_chart_analysis_prompt(chart_type)

        analyze_image(
          image_data: image_data,
          prompt: prompt,
          options: {
            min_confidence: 0.65,
            analysis_type: "chart_analysis",
            chart_type: chart_type
          }
        )
      end

      # 대화형 이미지 분석
      def analyze_in_conversation(image_data:, message:, conversation_history: [])
        multimodal_service = OpenrouterMultimodalService.new(tier: @default_tier)

        result = multimodal_service.analyze_image_in_conversation(
          image_data: image_data,
          message: message,
          conversation_history: conversation_history,
          user: @user
        )

        # 품질 검증
        if result[:confidence_score] < @quality_threshold
          enhance_with_context(result, conversation_history)
        else
          result
        end
      end

      private

      def perform_analysis(image_data:, prompt:, options:)
        start_time = Time.current

        # 초기 티어 결정
        initial_tier = determine_initial_tier(options)

        # 멀티모달 서비스 초기화
        service = OpenrouterMultimodalService.new(tier: initial_tier)

        # 분석 수행 (자동 폴백 포함)
        result = service.analyze_image_with_context(
          image_data: image_data,
          text_prompt: prompt,
          user: @user,
          context: {
            min_confidence: options[:min_confidence] || @quality_threshold,
            analysis_type: options[:analysis_type],
            **options[:context].to_h
          }
        )

        # 결과 포맷팅
        format_result(result, start_time, options)

      rescue StandardError => e
        Rails.logger.error("Multimodal coordination failed: #{e.message}")
        error_fallback(prompt, e, start_time)
      end

      def determine_initial_tier(options)
        # 우선순위별 티어 결정 로직
        if options[:force_tier]
          return options[:force_tier].to_sym
        end

        # 쿼리 복잡도 분석
        complexity_analysis = @complexity_analyzer.analyze(
          options[:prompt] || "",
          {
            has_image: true,
            priority: options[:priority],
            expert_mode: options[:expert_mode],
            previous_failures: options[:previous_failures] || 0,
            conversation_length: options[:conversation_length] || 0
          }
        )

        Rails.logger.info("Query complexity analysis: #{complexity_analysis[:reasoning]}")

        # 복잡도 기반 티어 결정
        recommended_tier = complexity_analysis[:recommended_tier]

        # 특수 케이스 처리
        if options[:analysis_type] == "critical_formula" && recommended_tier == :cost_effective
          :balanced  # 중요한 수식은 최소 중간 티어
        elsif options[:require_high_accuracy]
          :premium   # 높은 정확도 요구시 최상위 티어
        else
          recommended_tier
        end
      end

      def build_excel_analysis_prompt(context)
        base_prompt = <<~PROMPT
          이 Excel 스크린샷을 분석해주세요. 다음 항목들을 포함해서 답변해주세요:

          1. 보이는 데이터의 구조와 형식
          2. 사용된 수식이나 함수 (보이는 경우)
          3. 데이터의 패턴이나 특징
          4. 잠재적 문제점이나 개선 사항
        PROMPT

        if context[:specific_question]
          base_prompt += "\n\n특별히 주목할 점: #{context[:specific_question]}"
        end

        if context[:error_context]
          base_prompt += "\n\n오류 상황: #{context[:error_context]}"
        end

        base_prompt
      end

      def build_chart_analysis_prompt(chart_type)
        type_specific = case chart_type
        when "pie"
                         "원형 차트의 각 섹션 비율과 전체 합계가 100%인지 확인해주세요."
        when "line"
                         "선 그래프의 추세와 변화 패턴을 분석해주세요."
        when "bar"
                         "막대 그래프의 각 항목 비교와 상대적 크기를 설명해주세요."
        else
                         "차트의 유형을 식별하고 주요 특징을 설명해주세요."
        end

        <<~PROMPT
          Excel 차트 이미지를 분석합니다.

          #{type_specific}

          분석 항목:
          - 데이터의 주요 인사이트
          - 시각적 표현의 적절성
          - 개선 가능한 부분
          - 데이터의 정확성 검증
        PROMPT
      end

      def format_result(raw_result, start_time, options)
        {
          success: true,
          analysis: raw_result[:analysis],
          structured_data: raw_result[:structured_analysis],
          confidence_score: raw_result[:confidence_score],
          model_used: raw_result[:model],
          tier_used: raw_result[:tier],
          processing_time: Time.current - start_time,

          # 폴백 정보 (있는 경우)
          fallback_info: raw_result[:fallback_details],

          # 비용 정보
          cost_info: {
            credits_used: raw_result[:credits_used],
            estimated_cost: raw_result[:cost_breakdown][:current_cost],
            tier_comparison: raw_result[:cost_breakdown][:comparisons]
          },

          # 품질 지표
          quality_metrics: calculate_quality_metrics(raw_result),

          # 추가 메타데이터
          metadata: {
            analysis_type: options[:analysis_type],
            request_id: SecureRandom.uuid,
            timestamp: Time.current
          }
        }
      end

      def calculate_quality_metrics(result)
        {
          confidence_score: result[:confidence_score],
          response_completeness: assess_completeness(result[:analysis]),
          excel_relevance: assess_excel_relevance(result[:analysis]),
          actionable_insights: count_actionable_insights(result[:analysis]),
          quality_tier: determine_quality_tier(result[:confidence_score])
        }
      end

      def assess_completeness(analysis)
        return 0.0 if analysis.blank?

        # 응답의 완성도 평가
        indicators = {
          has_introduction: analysis.match?(/^[^.!?]+[.!?]/),
          has_details: analysis.length > 200,
          has_structure: analysis.include?("\n") || analysis.match?(/\d+[.)]/),
          has_conclusion: analysis.match?(/[.!?]\s*$/),
          has_specific_values: analysis.match?(/\d+/)
        }

        score = indicators.values.count(true) / indicators.size.to_f
        score.round(2)
      end

      def assess_excel_relevance(analysis)
        return 0.0 if analysis.blank?

        excel_keywords = %w[
          cell formula worksheet column row chart graph pivot
          vlookup sum average count if concatenate index match
          셀 수식 워크시트 열 행 차트 그래프 피벗
        ]

        keywords_found = excel_keywords.count { |kw| analysis.downcase.include?(kw) }
        [ keywords_found / 5.0, 1.0 ].min.round(2)
      end

      def count_actionable_insights(analysis)
        return 0 if analysis.blank?

        # 실행 가능한 인사이트 패턴
        action_patterns = [
          /(?:제안|추천|권장|suggest|recommend)/i,
          /(?:해야|하면 좋|하는 것이 좋|should|could|need to)/i,
          /(?:개선|향상|최적화|improve|enhance|optimize)/i,
          /(?:문제|오류|이슈|problem|error|issue)/i
        ]

        action_patterns.count { |pattern| analysis.match?(pattern) }
      end

      def determine_quality_tier(confidence_score)
        case confidence_score
        when 0.85..1.0 then "excellent"
        when 0.75..0.85 then "good"
        when 0.65..0.75 then "acceptable"
        when 0.5..0.65 then "marginal"
        else "poor"
        end
      end

      def enhance_with_context(result, conversation_history)
        # 대화 맥락을 활용한 결과 향상
        context_summary = summarize_conversation(conversation_history)

        result[:enhanced_analysis] = <<~ENHANCED
          [대화 맥락 기반 분석]
          #{context_summary}

          [이미지 분석 결과]
          #{result[:analysis]}
        ENHANCED

        result[:confidence_score] = [ result[:confidence_score] + 0.1, 1.0 ].min
        result
      end

      def summarize_conversation(history)
        return "새로운 대화입니다." if history.empty?

        recent_messages = history.last(3).map { |msg| "#{msg[:role]}: #{msg[:content]}" }
        "최근 대화:\n#{recent_messages.join("\n")}"
      end

      def error_fallback(prompt, error, start_time)
        {
          success: false,
          error: error.message,
          analysis: "이미지 분석 중 오류가 발생했습니다. 텍스트로 질문을 설명해주시면 도움을 드리겠습니다.",
          confidence_score: 0.0,
          processing_time: Time.current - start_time,
          fallback_suggestions: [
            "이미지 없이 문제를 텍스트로 설명해주세요",
            "다른 형식의 이미지로 다시 시도해보세요",
            "스크린샷 대신 Excel 파일을 직접 업로드해보세요"
          ]
        }
      end

      def generate_cache_key(image_data, prompt)
        image_hash = Digest::SHA256.hexdigest(image_data)
        prompt_hash = Digest::SHA256.hexdigest(prompt)
        "multimodal:#{@user.id}:#{image_hash}:#{prompt_hash}"
      end
    end
  end
end
