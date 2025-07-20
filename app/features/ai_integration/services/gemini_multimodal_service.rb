# frozen_string_literal: true

module AiIntegration
  module Services
    # Gemini 1.5 Flash 기반 멀티모달 AI 서비스 (40배 비용 절감)
    class GeminiMultimodalService
      include HTTParty
      include Memoist

      base_uri "https://generativelanguage.googleapis.com"

      # Gemini 1.5 Flash: $0.075/1M 토큰 (Claude 대비 40배 저렴)
      MODEL_CONFIG = {
        model: "gemini-1.5-flash",
        cost_per_million_tokens: 0.075,
        max_tokens: 1_048_576, # 1M 토큰
        multimodal_features: %w[text image video audio code].freeze
      }.freeze

      def initialize
        @api_key = Rails.application.credentials.google_ai_api_key
        @usage_tracker = AiIntegration::Services::UsageTracker.new
        @cache = Rails.cache
      end

      # 이미지 + 텍스트 분석 (Excel 스크린샷 + 설명)
      def analyze_image_with_context(image_data:, text_prompt:, user:, context: {})
        start_time = Time.current

        Rails.logger.info("Starting Gemini multimodal analysis: image + text")

        begin
          # 이미지 전처리
          processed_image = preprocess_image(image_data)

          # Gemini API 호출
          response = call_gemini_api(
            text: text_prompt,
            image: processed_image,
            context: context
          )

          # 응답 처리
          result = process_gemini_response(response)

          # 사용량 추적
          credits_used = estimate_credits_used(text_prompt, processed_image)
          track_usage(user, credits_used, start_time)

          {
            analysis: result[:content],
            structured_analysis: result[:structured_data],
            confidence_score: result[:confidence] || 0.85,
            credits_used: credits_used,
            cost_saved: calculate_cost_savings(credits_used),
            provider: "gemini",
            model: MODEL_CONFIG[:model],
            processing_time: Time.current - start_time,
            multimodal_features: [ "image", "text" ]
          }

        rescue StandardError => e
          Rails.logger.error("Gemini multimodal analysis failed: #{e.message}")
          fallback_analysis(text_prompt, user, start_time)
        end
      end

      # Excel 차트/그래프 분석
      def analyze_excel_visualization(image_data:, analysis_type: "chart_analysis", user:)
        start_time = Time.current

        prompt = build_excel_visualization_prompt(analysis_type)

        response = analyze_image_with_context(
          image_data: image_data,
          text_prompt: prompt,
          user: user,
          context: { analysis_type: analysis_type }
        )

        # Excel 특화 후처리
        enhance_excel_analysis_response(response, analysis_type)
      end

      # 비디오 기반 Excel 튜토리얼 분석 (Gemini 고유 기능)
      def analyze_excel_tutorial_video(video_data:, user:, duration_seconds: nil)
        start_time = Time.current

        Rails.logger.info("Analyzing Excel tutorial video with Gemini (#{duration_seconds}s)")

        # Gemini의 비디오 처리 능력 활용 (2시간까지)
        if duration_seconds && duration_seconds > 7200 # 2시간 초과
          return error_response("Video too long. Gemini supports up to 2 hours.")
        end

        prompt = build_video_analysis_prompt

        begin
          response = call_gemini_video_api(
            video: video_data,
            text: prompt
          )

          result = process_gemini_response(response)
          credits_used = estimate_video_tokens(duration_seconds)

          track_usage(user, credits_used, start_time)

          {
            tutorial_analysis: result[:content],
            key_steps: extract_tutorial_steps(result),
            excel_functions: identify_excel_functions(result),
            difficulty_level: assess_difficulty(result),
            credits_used: credits_used,
            provider: "gemini",
            processing_time: Time.current - start_time
          }

        rescue StandardError => e
          Rails.logger.error("Video analysis failed: #{e.message}")
          fallback_analysis("Video analysis request", user, start_time)
        end
      end

      private

      def call_gemini_api(text:, image: nil, context: {})
        cache_key = generate_cache_key(text, image)
        cached_result = @cache.read(cache_key)
        return cached_result if cached_result

        request_body = build_request_body(text, image, context)

        response = self.class.post(
          "/v1beta/models/#{MODEL_CONFIG[:model]}:generateContent",
          headers: {
            "Content-Type" => "application/json",
            "x-goog-api-key" => @api_key
          },
          body: request_body.to_json,
          timeout: 30
        )

        if response.success?
          result = response.parsed_response
          @cache.write(cache_key, result, expires_in: 1.hour)
          result
        else
          raise "Gemini API error: #{response.code} - #{response.body}"
        end
      end

      def call_gemini_video_api(video:, text:)
        # Gemini 비디오 분석 API 호출
        request_body = {
          contents: [
            {
              parts: [
                {
                  text: text
                },
                {
                  inline_data: {
                    mime_type: detect_video_mime_type(video),
                    data: encode_video_data(video)
                  }
                }
              ]
            }
          ],
          generationConfig: {
            temperature: 0.4,
            topK: 32,
            topP: 1,
            maxOutputTokens: 8192
          }
        }

        self.class.post(
          "/v1beta/models/#{MODEL_CONFIG[:model]}:generateContent",
          headers: {
            "Content-Type" => "application/json",
            "x-goog-api-key" => @api_key
          },
          body: request_body.to_json,
          timeout: 120 # 비디오는 더 긴 타임아웃
        )
      end

      def build_request_body(text, image, context)
        parts = [ { text: text } ]

        if image
          parts << {
            inline_data: {
              mime_type: detect_image_mime_type(image),
              data: encode_image_data(image)
            }
          }
        end

        {
          contents: [ { parts: parts } ],
          generationConfig: {
            temperature: context[:temperature] || 0.4,
            topK: 32,
            topP: 1,
            maxOutputTokens: context[:max_tokens] || 4096
          },
          safetySettings: [
            {
              category: "HARM_CATEGORY_HARASSMENT",
              threshold: "BLOCK_MEDIUM_AND_ABOVE"
            },
            {
              category: "HARM_CATEGORY_HATE_SPEECH",
              threshold: "BLOCK_MEDIUM_AND_ABOVE"
            }
          ]
        }
      end

      def preprocess_image(image_data)
        # 이미지 크기 최적화 (Gemini 제한: 20MB)
        return image_data if image_data.bytesize <= 20.megabytes

        # 이미지 압축 또는 리사이즈
        compress_image(image_data)
      end

      def compress_image(image_data)
        # MiniMagick을 사용한 이미지 압축
        image = MiniMagick::Image.read(image_data)

        # 해상도가 너무 높으면 리사이즈
        if image.width > 2048 || image.height > 2048
          image.resize "2048x2048>"
        end

        # 품질 조정 (JPEG만)
        if image.mime_type.include?("jpeg")
          image.format "jpeg"
          image.quality 85
        end

        image.to_blob
      rescue StandardError => e
        Rails.logger.warn("Image compression failed: #{e.message}")
        image_data # 원본 반환
      end

      def detect_image_mime_type(image_data)
        # 이미지 MIME 타입 감지
        return "image/jpeg" if image_data[0, 4] == "\xFF\xD8\xFF".b
        return "image/png" if image_data[0, 8] == "\x89PNG\r\n\x1A\n".b
        return "image/gif" if image_data[0, 6] == "GIF87a".b || image_data[0, 6] == "GIF89a".b
        return "image/webp" if image_data[8, 4] == "WEBP".b

        "image/jpeg" # 기본값
      end

      def detect_video_mime_type(video_data)
        # 비디오 MIME 타입 감지
        return "video/mp4" if video_data[4, 4] == "ftyp".b
        return "video/webm" if video_data[0, 4] == "\x1A\x45\xDF\xA3".b

        "video/mp4" # 기본값
      end

      def encode_image_data(image_data)
        Base64.strict_encode64(image_data)
      end

      def encode_video_data(video_data)
        Base64.strict_encode64(video_data)
      end

      def process_gemini_response(response)
        return { content: "No response", confidence: 0.0 } unless response

        candidates = response.dig("candidates")
        return { content: "No candidates", confidence: 0.0 } unless candidates&.any?

        content = candidates.first.dig("content", "parts", 0, "text")
        safety_ratings = candidates.first.dig("safetyRatings") || []

        # 안전성 점수를 신뢰도로 변환
        confidence = calculate_confidence_from_safety(safety_ratings)

        # 구조화된 데이터 추출 시도
        structured_data = extract_structured_data(content)

        {
          content: content || "Unable to generate response",
          confidence: confidence,
          structured_data: structured_data,
          safety_ratings: safety_ratings
        }
      end

      def calculate_confidence_from_safety(safety_ratings)
        return 0.8 if safety_ratings.empty?

        # 안전성 등급을 신뢰도로 변환
        total_score = safety_ratings.sum do |rating|
          case rating["probability"]
          when "NEGLIGIBLE" then 1.0
          when "LOW" then 0.9
          when "MEDIUM" then 0.7
          when "HIGH" then 0.3
          else 0.5
          end
        end

        [ total_score / safety_ratings.size, 1.0 ].min
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
        image_tokens = image ? 512 : 0 # 이미지당 고정 토큰

        text_tokens + image_tokens
      end

      def estimate_video_tokens(duration_seconds)
        return 1000 unless duration_seconds

        # 비디오 토큰 추정: 초당 약 10토큰
        base_tokens = 500
        duration_tokens = duration_seconds * 10

        base_tokens + duration_tokens
      end

      def calculate_cost_savings(credits_used)
        # Claude 3 Opus와 비교한 비용 절감
        gemini_cost = (credits_used / 1_000_000.0) * MODEL_CONFIG[:cost_per_million_tokens]
        claude_cost = (credits_used / 1_000_000.0) * 15.0 # Claude 3 Opus 추정

        {
          gemini_cost: gemini_cost.round(4),
          claude_cost: claude_cost.round(4),
          savings: (claude_cost - gemini_cost).round(4),
          savings_percentage: (((claude_cost - gemini_cost) / claude_cost) * 100).round(1)
        }
      end

      def track_usage(user, credits_used, start_time)
        @usage_tracker.track_request(
          user: user,
          provider: "gemini",
          model: MODEL_CONFIG[:model],
          credits_used: credits_used,
          cost: (credits_used / 1_000_000.0) * MODEL_CONFIG[:cost_per_million_tokens],
          processing_time: Time.current - start_time,
          success: true,
          features: [ "multimodal", "image_analysis" ]
        )
      end

      def build_excel_visualization_prompt(analysis_type)
        case analysis_type
        when "chart_analysis"
          <<~PROMPT
            Analyze this Excel chart/graph image and provide:
            1. Chart type identification
            2. Data interpretation
            3. Potential issues or improvements
            4. Suggested optimizations

            Please provide a detailed analysis in JSON format with structured data.
          PROMPT
        when "formula_visualization"
          <<~PROMPT
            Analyze this Excel formula or spreadsheet screenshot:
            1. Identify the formulas being used
            2. Check for errors or inefficiencies
            3. Suggest improvements or alternatives
            4. Provide step-by-step explanations

            Format the response as structured JSON data.
          PROMPT
        else
          "Analyze this Excel-related image and provide insights about the data, formulas, or visualization shown."
        end
      end

      def build_video_analysis_prompt
        <<~PROMPT
          Analyze this Excel tutorial video and provide:
          1. Summary of key steps demonstrated
          2. Excel functions and features used
          3. Difficulty level assessment
          4. Key learning points
          5. Common mistakes to avoid
          6. Alternative approaches or improvements

          Please structure the response with clear sections and actionable insights.
        PROMPT
      end

      def enhance_excel_analysis_response(response, analysis_type)
        enhanced = response.dup

        case analysis_type
        when "chart_analysis"
          enhanced[:chart_improvements] = extract_chart_improvements(response[:analysis])
          enhanced[:data_quality_score] = assess_data_quality(response[:analysis])
        when "formula_visualization"
          enhanced[:formula_complexity] = assess_formula_complexity(response[:analysis])
          enhanced[:optimization_suggestions] = extract_optimizations(response[:analysis])
        end

        enhanced
      end

      def extract_tutorial_steps(result)
        content = result[:content] || ""

        # 단계별 내용 추출
        steps = content.scan(/(?:step|단계)\s*\d+[:\-]?\s*(.+?)(?=(?:step|단계)\s*\d+|$)/i)
        steps.flatten.map(&:strip).reject(&:empty?)
      end

      def identify_excel_functions(result)
        content = result[:content] || ""

        # Excel 함수들 추출
        excel_functions = content.scan(/\b[A-Z]+\([^)]*\)/).uniq
        standard_functions = %w[SUM AVERAGE VLOOKUP HLOOKUP INDEX MATCH IF COUNTIF SUMIF]

        {
          detected_functions: excel_functions,
          standard_functions_used: standard_functions.select { |f| content.include?(f) }
        }
      end

      def assess_difficulty(result)
        content = result[:content] || ""

        difficulty_indicators = {
          beginner: %w[basic simple fundamental introduction],
          intermediate: %w[moderate complex advanced features],
          expert: %w[expert professional sophisticated automation]
        }

        scores = difficulty_indicators.map do |level, keywords|
          score = keywords.count { |keyword| content.downcase.include?(keyword) }
          [ level, score ]
        end

        scores.max_by { |_, score| score }.first
      end

      def extract_chart_improvements(analysis)
        # 차트 개선사항 추출 로직
        improvements = []

        improvements << "Add data labels" if analysis.include?("label")
        improvements << "Improve color scheme" if analysis.include?("color")
        improvements << "Adjust axis scaling" if analysis.include?("axis") || analysis.include?("scale")

        improvements
      end

      def assess_data_quality(analysis)
        # 데이터 품질 점수 계산
        quality_score = 0.7 # 기본 점수

        quality_score += 0.1 if analysis.include?("accurate")
        quality_score += 0.1 if analysis.include?("complete")
        quality_score -= 0.2 if analysis.include?("missing") || analysis.include?("error")

        [ quality_score, 1.0 ].min
      end

      def assess_formula_complexity(analysis)
        # 수식 복잡도 평가
        if analysis.include?("nested") || analysis.include?("complex")
          "high"
        elsif analysis.include?("moderate") || analysis.include?("intermediate")
          "medium"
        else
          "low"
        end
      end

      def extract_optimizations(analysis)
        # 최적화 제안 추출
        optimizations = []

        optimizations << "Replace VLOOKUP with INDEX/MATCH" if analysis.include?("VLOOKUP")
        optimizations << "Use array formulas" if analysis.include?("array")
        optimizations << "Reduce formula length" if analysis.include?("long") || analysis.include?("complex")

        optimizations
      end

      def fallback_analysis(prompt, user, start_time)
        # Gemini 실패시 텍스트 기반 분석으로 폴백
        Rails.logger.warn("Falling back to text-only analysis")

        basic_service = AiIntegration::Services::ModernizedMultiProviderService.new(tier: 1)
        basic_service.analyze_with_intelligent_routing(
          file_data: { name: "image_analysis_fallback" },
          user: user,
          errors: [ { type: "multimodal_analysis", message: prompt } ]
        )
      end

      def error_response(message)
        {
          error: true,
          message: message,
          provider: "gemini",
          processing_time: 0
        }
      end

      def generate_cache_key(text, image)
        content_hash = Digest::SHA256.hexdigest("#{text}#{image&.bytesize}")
        "gemini_multimodal:#{content_hash}"
      end

      # 메모이제이션으로 API 키 검증 최적화
      # memoize :detect_image_mime_type, :detect_video_mime_type
    end
  end
end
