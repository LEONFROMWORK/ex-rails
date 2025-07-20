# frozen_string_literal: true

module AiIntegration
  module Services
    # OpenRouter 통합 멀티모달 AI 서비스 (하나의 API 키로 모든 모델 사용)
    class OpenrouterMultimodalService
      include HTTParty
      include Memoist

      base_uri "https://openrouter.ai/api/v1"

      # OpenRouter에서 지원하는 멀티모달 모델들
      MULTIMODAL_MODELS = {
        cost_effective: {
          model: "google/gemini-flash-1.5",
          cost_per_million_tokens: 0.075,
          features: %w[text image],
          max_tokens: 1_048_576
        },
        balanced: {
          model: "anthropic/claude-3-haiku",
          cost_per_million_tokens: 0.25,
          features: %w[text image],
          max_tokens: 200_000
        },
        premium: {
          model: "openai/gpt-4-vision-preview",
          cost_per_million_tokens: 10.0,
          features: %w[text image],
          max_tokens: 4_096
        }
      }.freeze

      def initialize(tier: :cost_effective)
        @model_config = MULTIMODAL_MODELS[tier]
        @api_key = Rails.application.credentials.openrouter_api_key
        @usage_tracker = AiIntegration::Services::UsageTracker.new
        @cache = Rails.cache
        @tier = tier

        # 회로 차단기 초기화
        @circuit_breaker = CircuitBreakerService.new(
          failure_threshold: 3,
          timeout: 120.seconds,
          success_threshold: 2
        )

        # 재시도 서비스 초기화
        @retry_service = RetryWithBackoffService.new(
          max_retries: 2,
          base_delay: 1.0,
          max_delay: 8.0,
          use_circuit_breaker: false # 수동으로 관리
        )

        # 캐시 서비스 초기화
        @semantic_cache = SemanticCacheService.new

        # 모니터링 서비스
        @monitoring = QualityMonitoringService.instance
      end

      # 이미지 + 텍스트 분석 (Excel 스크린샷 + 설명)
      def analyze_image_with_context(image_data:, text_prompt:, user:, context: {})
        start_time = Time.current

        # 캐시 확인 (이미지 해시 + 텍스트 조합)
        cache_key = generate_cache_key(image_data, text_prompt)
        cached_response = @semantic_cache.get(cache_key, context) unless context[:skip_cache]

        if cached_response
          Rails.logger.info("Semantic cache hit for multimodal analysis")
          # 캐시 응답에 추가 정보 포함
          cached_response["processing_time"] = Time.current - start_time
          cached_response["cache_hit"] = true

          # 모니터링
          @monitoring.analyze_response(cached_response)

          return cached_response.deep_symbolize_keys
        end

        # 폴백을 위해 이미지 데이터 저장
        @current_image_data = image_data
        @attempt_count = context[:attempt_count] || 1

        Rails.logger.info("Starting OpenRouter multimodal analysis with #{@model_config[:model]} (attempt #{@attempt_count})")

        begin
          # 이미지 전처리
          processed_image = preprocess_image(image_data)

          # OpenRouter API 호출
          response = call_openrouter_api(
            text: text_prompt,
            image: processed_image,
            context: context
          )

          # 응답 처리
          result = process_response(response)

          # 품질 점수 계산
          confidence_score = calculate_confidence_score(result)

          # 품질이 낮고 더 높은 티어가 있다면 폴백
          min_acceptable_confidence = context[:min_confidence] || 0.65
          if confidence_score < min_acceptable_confidence && !context[:is_final_attempt]
            Rails.logger.warn("Low confidence score #{confidence_score} for #{@tier}, attempting fallback")

            # 다음 티어가 있는지 확인
            next_tier = get_next_tier(@tier)
            if next_tier
              return fallback_to_next_tier(
                image_data: image_data,
                text_prompt: text_prompt,
                user: user,
                context: context.merge(
                  previous_result: result,
                  previous_confidence: confidence_score
                ),
                start_time: start_time
              )
            end
          end

          # 사용량 추적
          credits_used = result[:usage][:total_tokens] || estimate_credits_used(text_prompt, processed_image)
          track_usage(user, credits_used, start_time)

          final_result = {
            analysis: result[:content],
            structured_analysis: extract_structured_data(result[:content]),
            confidence_score: confidence_score,
            credits_used: credits_used,
            cost_breakdown: calculate_cost_breakdown(credits_used),
            provider: "openrouter",
            model: @model_config[:model],
            tier: @tier,
            processing_time: Time.current - start_time,
            multimodal_features: @model_config[:features],
            is_fallback: context[:is_fallback] || false,
            original_tier: context[:original_tier] || @tier,
            attempt_count: @attempt_count,
            model_used: @model_config[:model],
            tier_used: @tier,
            success: true,
            quality_metrics: {
              confidence_score: confidence_score,
              quality_tier: determine_quality_tier(confidence_score)
            }
          }

          # 모니터링에 응답 분석 전송
          @monitoring.analyze_response(final_result)

          # 고품질 응답만 캐시에 저장
          if confidence_score >= 0.7 && !context[:skip_cache]
            @semantic_cache.set(cache_key, final_result, context)
          end

          final_result

        rescue StandardError => e
          Rails.logger.error("OpenRouter multimodal analysis failed: #{e.message}")
          fallback_analysis(text_prompt, user, start_time)
        end
      end

      # Excel 차트/그래프 분석
      def analyze_excel_visualization(image_data:, analysis_type: "chart_analysis", user:)
        prompt = build_excel_visualization_prompt(analysis_type)

        analyze_image_with_context(
          image_data: image_data,
          text_prompt: prompt,
          user: user,
          context: { analysis_type: analysis_type }
        )
      end

      # 대화형 이미지 분석 (챗봇에서 이미지 첨부시)
      def analyze_image_in_conversation(image_data:, message:, conversation_history: [], user:)
        # 대화 컨텍스트를 포함한 프롬프트 생성
        context_prompt = build_conversation_context_prompt(message, conversation_history)

        analyze_image_with_context(
          image_data: image_data,
          text_prompt: context_prompt,
          user: user,
          context: {
            conversation_mode: true,
            history_length: conversation_history.length
          }
        )
      end

      # 템플릿 기반 이미지 분석
      def analyze_with_template(image_data:, template_type:, user:, custom_questions: [])
        prompt = build_template_prompt(template_type, custom_questions)

        analyze_image_with_context(
          image_data: image_data,
          text_prompt: prompt,
          user: user,
          context: {
            template_type: template_type,
            custom_questions: custom_questions
          }
        )
      end

      private

      def call_openrouter_api(text:, image: nil, context: {})
        service_name = "openrouter_#{@model_config[:model].gsub('/', '_')}"

        # 회로 차단기와 재시도 로직을 통한 API 호출
        @circuit_breaker.call(service_name) do
          @retry_service.execute("#{service_name}_api_call") do
            messages = build_messages(text, image)

            request_body = {
              model: @model_config[:model],
              messages: messages,
              max_tokens: context[:max_tokens] || 4096,
              temperature: context[:temperature] || 0.4,
              top_p: context[:top_p] || 1.0,
              stream: false
            }

            # OpenRouter 전용 헤더
            headers = {
              "Content-Type" => "application/json",
              "Authorization" => "Bearer #{@api_key}",
              "HTTP-Referer" => Rails.application.credentials.app_url || "http://localhost:3000",
              "X-Title" => "ExcelApp AI Analysis"
            }

            Rails.logger.debug("OpenRouter API request to #{@model_config[:model]}")

            response = self.class.post(
              "/chat/completions",
              headers: headers,
              body: request_body.to_json,
              timeout: 60
            )

            # Rate limit 처리
            if response.code == 429
              retry_after = response.headers["retry-after"]&.to_i || 5
              raise OpenAI::RateLimitError.new("Rate limited. Retry after #{retry_after}s")
            end

            unless response.success?
              raise "OpenRouter API error: #{response.code} - #{response.body}"
            end

            response.parsed_response
          end
        end
      rescue CircuitBreakerService::CircuitOpenError => e
        Rails.logger.warn("Circuit breaker open for #{service_name}: #{e.message}")
        raise
      end

      def build_messages(text, image)
        content = [ { type: "text", text: text } ]

        if image
          # Base64 인코딩된 이미지 추가
          content << {
            type: "image_url",
            image_url: {
              url: "data:#{detect_image_mime_type(image)};base64,#{encode_image_data(image)}"
            }
          }
        end

        [
          {
            role: "user",
            content: content
          }
        ]
      end

      def preprocess_image(image_data)
        # 이미지 크기 최적화 (OpenRouter 모델별 제한)
        max_size = case @tier
        when :cost_effective then 20.megabytes  # Gemini Flash
        when :balanced then 5.megabytes         # Claude Haiku
        when :premium then 20.megabytes         # GPT-4V
        else 10.megabytes
        end

        return image_data if image_data.bytesize <= max_size

        compress_image(image_data, max_size)
      end

      def compress_image(image_data, max_size)
        # MiniMagick을 사용한 이미지 압축
        image = MiniMagick::Image.read(image_data)

        # 해상도 조정
        max_dimension = case @tier
        when :cost_effective then 2048
        when :balanced then 1568
        when :premium then 2048
        else 1024
        end

        if image.width > max_dimension || image.height > max_dimension
          image.resize "#{max_dimension}x#{max_dimension}>"
        end

        # 품질 조정하여 파일 크기 줄이기
        if image.mime_type.include?("jpeg")
          image.format "jpeg"
          quality = 85

          # 파일 크기가 여전히 크면 품질을 더 낮춤
          loop do
            image.quality quality
            compressed_data = image.to_blob
            break if compressed_data.bytesize <= max_size || quality <= 60
            quality -= 10
          end
        end

        image.to_blob
      rescue StandardError => e
        Rails.logger.warn("Image compression failed: #{e.message}")
        image_data # 원본 반환
      end

      def detect_image_mime_type(image_data)
        return "image/jpeg" if image_data[0, 4] == "\xFF\xD8\xFF".b
        return "image/png" if image_data[0, 8] == "\x89PNG\r\n\x1A\n".b
        return "image/gif" if image_data[0, 6] == "GIF87a".b || image_data[0, 6] == "GIF89a".b
        return "image/webp" if image_data[8, 4] == "WEBP".b

        "image/jpeg" # 기본값
      end

      def encode_image_data(image_data)
        Base64.strict_encode64(image_data)
      end

      def process_response(response)
        choice = response.dig("choices", 0)
        return { content: "No response generated", usage: {} } unless choice

        content = choice.dig("message", "content") || "Unable to analyze image"
        usage = response["usage"] || {}

        {
          content: content,
          usage: usage,
          finish_reason: choice["finish_reason"]
        }
      end

      def calculate_confidence_score(result)
        # 멀티모달 응답의 품질을 정교하게 평가
        content = result[:content]
        return 0.2 if content.blank?

        # 모델별 기본 신뢰도
        base_confidence = case @tier
        when :cost_effective then 0.6  # Gemini Flash
        when :balanced then 0.7         # Claude Haiku
        when :premium then 0.85         # GPT-4V
        else 0.5
        end

        confidence = base_confidence
        content_lower = content.downcase

        # 1. 이미지 인식 관련 키워드 체크 (이미지를 실제로 "봤다"는 증거)
        image_recognition_keywords = [
          "보입니다", "확인됩니다", "나타나", "표시되", "보이는",
          "스크린샷", "이미지", "화면", "그림", "시각적",
          "shows", "displays", "appears", "visible", "screenshot"
        ]

        image_recognition_score = image_recognition_keywords.count { |keyword|
          content_lower.include?(keyword)
        }
        confidence += [ image_recognition_score * 0.02, 0.1 ].min

        # 2. Excel 특화 분석 체크
        excel_analysis_indicators = {
          # 구체적인 셀 참조
          cell_references: /[A-Z]+\d+/,
          # 수식 언급
          formula_mentions: /(?:수식|formula|함수|function)/i,
          # 데이터 타입 언급
          data_types: /(?:숫자|텍스트|날짜|number|text|date)/i,
          # Excel 기능 언급
          excel_features: /(?:차트|그래프|피벗|매크로|chart|graph|pivot|macro)/i,
          # 구체적인 값 언급
          specific_values: /(?:\d+[\.,]\d+|\$[\d,]+|%\d+)/
        }

        excel_score = excel_analysis_indicators.count do |_, pattern|
          content.match?(pattern)
        end
        confidence += [ excel_score * 0.03, 0.15 ].min

        # 3. 구조화된 응답 체크
        structure_indicators = {
          bullet_points: /(?:^[-*•]\s|\n[-*•]\s)/m,
          numbered_list: /(?:^\d+[.)]\s|\n\d+[.)]\s)/m,
          sections: /(?:^#+\s|\n#+\s|^==+$|\n==+$)/m,
          code_blocks: /```[\s\S]*?```/m,
          emphasis: /(?:\*\*.*?\*\*|__.*?__)/
        }

        structure_score = structure_indicators.count do |_, pattern|
          content.match?(pattern)
        end
        confidence += [ structure_score * 0.02, 0.1 ].min

        # 4. 응답 길이 및 상세도
        word_count = content.split(/\s+/).length
        if word_count < 50
          confidence -= 0.1  # 너무 짧은 응답
        elsif word_count > 150
          confidence += 0.05  # 충분히 상세한 응답
        end

        # 5. 부정적 지표 (실패의 징후)
        failure_indicators = [
          "죄송", "확인할 수 없", "볼 수 없", "알 수 없", "이미지가 없",
          "sorry", "cannot see", "unable to view", "no image",
          "오류", "error", "실패", "failed"
        ]

        if failure_indicators.any? { |indicator| content_lower.include?(indicator) }
          confidence -= 0.2
        end

        # 6. finish_reason 체크
        if result[:finish_reason] == "length"
          confidence -= 0.05  # 토큰 제한으로 잘린 응답
        end

        # 최종 점수 정규화
        [ [ confidence, 0.1 ].max, 1.0 ].min
      end

      def calculate_cost_breakdown(credits_used)
        model_cost = (credits_used.to_f / 1_000_000) * @model_config[:cost_per_million_tokens]

        # 다른 모델들과 비교
        comparisons = MULTIMODAL_MODELS.map do |tier, config|
          next if tier == @tier

          comparison_cost = (credits_used.to_f / 1_000_000) * config[:cost_per_million_tokens]
          {
            tier: tier,
            model: config[:model],
            cost: comparison_cost.round(4),
            savings: (comparison_cost - model_cost).round(4)
          }
        end.compact

        {
          current_cost: model_cost.round(4),
          current_model: @model_config[:model],
          tier: @tier,
          comparisons: comparisons,
          credits_used: credits_used
        }
      end

      def build_excel_visualization_prompt(analysis_type)
        case analysis_type
        when "chart_analysis"
          <<~PROMPT
            분석할 Excel 차트/그래프 이미지입니다. 다음 항목들을 분석해주세요:

            1. **차트 유형 식별**: 어떤 종류의 차트인지 (막대, 선, 원형, 산점도 등)
            2. **데이터 해석**: 차트가 보여주는 핵심 인사이트
            3. **트렌드 분석**: 데이터에서 나타나는 패턴이나 추세
            4. **개선 제안**: 차트의 가독성이나 효과성을 높일 수 있는 방법
            5. **잠재적 문제점**: 데이터 표현의 오류나 개선이 필요한 부분

            구조화된 형태로 분석 결과를 제공해주세요.
          PROMPT
        when "formula_analysis"
          <<~PROMPT
            Excel 수식이나 스프레드시트 스크린샷입니다. 다음을 분석해주세요:

            1. **수식 식별**: 사용된 Excel 함수들과 수식 구조
            2. **로직 검증**: 수식의 논리적 정확성
            3. **최적화 제안**: 더 효율적인 수식이나 함수 사용법
            4. **오류 검사**: 잠재적인 계산 오류나 참조 오류
            5. **대안 제시**: 같은 결과를 얻을 수 있는 다른 방법들

            실용적인 개선 방안을 포함해서 답변해주세요.
          PROMPT
        when "data_validation"
          <<~PROMPT
            Excel 데이터의 스크린샷입니다. 데이터 품질을 검증해주세요:

            1. **데이터 일관성**: 형식과 패턴의 일관성 확인
            2. **완성도 검사**: 누락된 데이터나 공백 식별
            3. **이상값 탐지**: 비정상적인 값이나 패턴
            4. **구조 분석**: 데이터 구조의 적절성
            5. **정리 제안**: 데이터 정리 및 정규화 방안

            발견된 문제점과 해결 방안을 명확히 제시해주세요.
          PROMPT
        else
          "이 Excel 관련 이미지를 분석하고 개선점이나 인사이트를 제공해주세요."
        end
      end

      def build_conversation_context_prompt(message, history)
        context = if history.any?
          recent_context = history.last(3).map { |msg| "#{msg[:role]}: #{msg[:content]}" }.join("\n")
          "대화 맥락:\n#{recent_context}\n\n"
        else
          ""
        end

        <<~PROMPT
          #{context}사용자 질문: #{message}

          첨부된 이미지와 관련하여 사용자의 질문에 답변해주세요.#{' '}
          Excel이나 스프레드시트 관련 내용이라면 구체적인 분석과 개선 제안을 포함해주세요.
        PROMPT
      end

      def build_template_prompt(template_type, custom_questions)
        base_prompts = {
          financial: "재무 데이터 분석 관점에서 이 이미지를 검토해주세요.",
          operational: "운영 효율성 관점에서 이 데이터를 분석해주세요.",
          academic: "학술 연구 관점에서 이 데이터의 타당성을 검토해주세요.",
          general: "전반적인 관점에서 이 Excel 내용을 분석해주세요."
        }

        base_prompt = base_prompts[template_type.to_sym] || base_prompts[:general]

        if custom_questions.any?
          questions_text = custom_questions.each_with_index.map { |q, i| "#{i+1}. #{q}" }.join("\n")
          base_prompt += "\n\n추가 질문들:\n#{questions_text}"
        end

        base_prompt
      end

      def extract_structured_data(content)
        # JSON 형태의 구조화된 데이터 추출 시도
        return {} unless content

        # JSON 블록 찾기
        json_match = content.match(/```json\s*(\{.*?\})\s*```/m)
        return {} unless json_match

        begin
          JSON.parse(json_match[1])
        rescue JSON::ParserError
          {}
        end
      end

      def estimate_credits_used(text, image)
        text_tokens = (text.length / 4.0).ceil
        image_tokens = image ? calculate_image_tokens(image) : 0

        text_tokens + image_tokens
      end

      def calculate_image_tokens(image_data)
        # 모델별 이미지 토큰 계산
        case @tier
        when :cost_effective # Gemini Flash
          512 # 고정 토큰
        when :balanced # Claude Haiku
          # 이미지 크기 기반 계산
          (image_data.bytesize / 1024.0 * 1.2).ceil
        when :premium # GPT-4V
          # 해상도 기반 복잡한 계산
          765 # 기본값 (OpenAI 문서 기준)
        else
          400
        end
      end

      def track_usage(user, credits_used, start_time)
        @usage_tracker.track_request(
          user: user,
          provider: "openrouter",
          model: @model_config[:model],
          credits_used: credits_used,
          cost: (credits_used / 1_000_000.0) * @model_config[:cost_per_million_tokens],
          processing_time: Time.current - start_time,
          success: true,
          features: [ "multimodal", "image_analysis" ]
        )
      end

      def fallback_analysis(prompt, user, start_time)
        # 현재 티어에서 다음 티어로 폴백
        next_tier = get_next_tier(@tier)

        if next_tier.nil?
          # 모든 멀티모달 옵션 소진 - 텍스트 전용으로 최종 폴백
          Rails.logger.warn("All multimodal tiers exhausted, falling back to text-only analysis")

          basic_service = AiIntegration::Services::ModernizedMultiProviderService.new(tier: 1)
          return basic_service.analyze_with_intelligent_routing(
            file_data: { name: "image_analysis_fallback" },
            user: user,
            errors: [ { type: "multimodal_analysis", message: prompt } ]
          )
        end

        Rails.logger.info("Falling back from #{@tier} to #{next_tier} tier for multimodal analysis")

        # 다음 티어의 멀티모달 서비스로 재시도
        fallback_service = self.class.new(tier: next_tier)
        fallback_service.analyze_image_with_context(
          image_data: @current_image_data,
          text_prompt: prompt,
          user: user,
          context: {
            is_fallback: true,
            original_tier: @tier,
            attempt_count: (@attempt_count || 1) + 1
          }
        )
      end

      def get_next_tier(current_tier)
        tier_order = [ :cost_effective, :balanced, :premium ]
        current_index = tier_order.index(current_tier)

        return nil if current_index.nil? || current_index >= tier_order.length - 1

        tier_order[current_index + 1]
      end

      def fallback_to_next_tier(image_data:, text_prompt:, user:, context:, start_time:)
        next_tier = get_next_tier(@tier)

        Rails.logger.info("Attempting multimodal fallback from #{@tier} to #{next_tier}")

        # 새로운 서비스 인스턴스 생성
        fallback_service = self.class.new(tier: next_tier)

        # 컨텍스트 업데이트
        updated_context = context.merge(
          is_fallback: true,
          original_tier: context[:original_tier] || @tier,
          attempt_count: @attempt_count + 1,
          fallback_chain: (context[:fallback_chain] || []) + [ {
            tier: @tier,
            model: @model_config[:model],
            confidence: context[:previous_confidence],
            reason: "low_confidence"
          } ]
        )

        # 최상위 티어인 경우 최종 시도임을 표시
        if next_tier == :premium
          updated_context[:is_final_attempt] = true
        end

        # 재귀적으로 분석 시도
        result = fallback_service.analyze_image_with_context(
          image_data: image_data,
          text_prompt: text_prompt,
          user: user,
          context: updated_context
        )

        # 원래 시작 시간 기준으로 전체 처리 시간 업데이트
        result[:total_processing_time] = Time.current - start_time
        result[:fallback_details] = {
          original_tier: context[:original_tier] || @tier,
          final_tier: next_tier,
          attempts: @attempt_count + 1,
          chain: updated_context[:fallback_chain]
        }

        result
      end

      def generate_cache_key(image_data, text_prompt)
        # 이미지 해시와 텍스트를 조합한 캐시 키 생성
        image_hash = Digest::SHA256.hexdigest(image_data)
        text_hash = Digest::SHA256.hexdigest(text_prompt)
        "multimodal:#{image_hash}:#{text_hash}"
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

      # 메모이제이션으로 성능 최적화 (Memoist gem 필요)
      # memoize :detect_image_mime_type
    end
  end
end
