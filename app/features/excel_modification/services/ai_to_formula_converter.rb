# frozen_string_literal: true

module ExcelModification
  module Services
    # Converts natural language requests to Excel formulas using AI
    # Follows SOLID principles - Single Responsibility: Convert text to formulas
    class AiToFormulaConverter
      include ActiveModel::Model

      attr_accessor :multimodal_service, :cache

      def initialize
        @multimodal_service = AiIntegration::Services::MultimodalCoordinatorService.new(
          user: User.system_user,
          default_tier: :balanced
        )
        @cache = Rails.cache
      end

      # Convert natural language to Excel formula
      def convert(text, context = {})
        return Common::Result.failure("Text cannot be blank") if text.blank?

        # Check cache first
        cache_key = generate_cache_key(text, context)
        cached_result = @cache.read(cache_key)
        return Common::Result.success(cached_result) if cached_result

        # Build prompt for AI
        prompt = build_conversion_prompt(text, context)

        # Use multimodal service for better understanding
        result = @multimodal_service.analyze_image(
          image_data: context[:screenshot] || dummy_image,
          prompt: prompt,
          options: {
            min_confidence: 0.7,
            analysis_type: "formula_generation"
          }
        )

        return result if result.failure?

        # Extract formula from AI response
        formula_data = extract_formula_from_response(result.value)

        # Validate formula with HyperFormula
        validation_result = validate_formula(formula_data[:formula])
        return validation_result if validation_result.failure?

        # Cache successful conversion
        @cache.write(cache_key, formula_data, expires_in: 24.hours)

        Common::Result.success(formula_data)
      rescue StandardError => e
        Rails.logger.error("AI to Formula conversion failed: #{e.message}")
        Common::Result.failure("Formula conversion failed: #{e.message}")
      end

      # Batch convert multiple requests
      def convert_batch(requests)
        results = requests.map do |request|
          {
            original_text: request[:text],
            context: request[:context],
            result: convert(request[:text], request[:context])
          }
        end

        successful = results.select { |r| r[:result].success? }
        failed = results.select { |r| r[:result].failure? }

        Common::Result.success({
          successful: successful,
          failed: failed,
          success_rate: successful.size.to_f / results.size
        })
      end

      private

      def build_conversion_prompt(text, context)
        base_prompt = <<~PROMPT
          사용자의 요청을 Excel 수식으로 변환해주세요.

          사용자 요청: "#{text}"

          컨텍스트:
          - 워크시트: #{context[:worksheet_name] || 'Sheet1'}
          - 선택된 셀: #{context[:selected_cell] || 'A1'}
          - 데이터 범위: #{context[:data_range] || '알 수 없음'}

          다음 형식으로 응답해주세요:
          ```json
          {
            "formula": "=수식",
            "explanation": "수식 설명",
            "cell_reference": "적용할 셀",
            "dependencies": ["참조되는 셀들"],
            "alternative_formulas": ["대체 수식들"]
          }
          ```

          주의사항:
          1. 정확한 Excel 수식 문법을 사용하세요
          2. 한국어 함수명이 아닌 영어 함수명을 사용하세요
          3. 셀 참조는 절대/상대 참조를 적절히 구분하세요
        PROMPT

        if context[:existing_formulas].present?
          base_prompt += "\n\n기존 수식들:\n#{context[:existing_formulas].join("\n")}"
        end

        base_prompt
      end

      def extract_formula_from_response(ai_response)
        # If response is already a hash, return it directly
        if ai_response.is_a?(Hash)
          return {
            formula: ai_response[:formula] || ai_response["formula"],
            explanation: ai_response[:explanation] || ai_response["explanation"] || "",
            cell_reference: ai_response[:cell_reference] || ai_response["cell_reference"] || "A1",
            dependencies: ai_response[:dependencies] || ai_response["dependencies"] || [],
            alternatives: ai_response[:alternatives] || ai_response["alternative_formulas"] || []
          }
        end

        # Try to parse JSON response
        json_match = ai_response.match(/```json\s*(\{.*?\})\s*```/m)

        if json_match
          begin
            data = JSON.parse(json_match[1])
            return {
              formula: data["formula"],
              explanation: data["explanation"],
              cell_reference: data["cell_reference"] || "A1",
              dependencies: data["dependencies"] || [],
              alternatives: data["alternative_formulas"] || []
            }
          rescue JSON::ParserError
            Rails.logger.warn("Failed to parse JSON from AI response")
          end
        end

        # Fallback: Extract formula using regex
        formula_match = ai_response.match(/=[\w\s\(\)\+\-\*\/\$\:,;]+/)

        {
          formula: formula_match ? formula_match[0] : nil,
          explanation: ai_response,
          cell_reference: "A1",
          dependencies: [],
          alternatives: []
        }
      end

      def validate_formula(formula)
        return Common::Result.failure("Formula not found") if formula.blank?

        # Use FormulaEngineClient to validate
        validation_result = FormulaEngineClient.validate_formula(formula)

        if validation_result.success? && validation_result.value[:valid]
          Common::Result.success
        else
          Common::Result.failure(
            "Invalid formula: #{validation_result.value[:errors]&.join(', ')}"
          )
        end
      rescue StandardError => e
        # If HyperFormula service is unavailable, do basic validation
        if formula.start_with?("=")
          Common::Result.success
        else
          Common::Result.failure("Formula must start with '='")
        end
      end

      def generate_cache_key(text, context)
        context_string = context.slice(:worksheet_name, :selected_cell, :data_range).to_json
        "ai_formula:#{Digest::SHA256.hexdigest("#{text}:#{context_string}")}"
      end

      def dummy_image
        # Create a minimal PNG for cases where no screenshot is provided
        "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1F\x15\xC4\x89\x00\x00\x00\rIDATx\x9Cc\xF8\x0F\x00\x00\x01\x01\x00\x05\xEE\xDE\xFD\xC0\x00\x00\x00\x00IEND\xAEB`\x82"
      end

      # Common formula patterns for quick conversion
      FORMULA_PATTERNS = {
        /평균|average/i => "AVERAGE",
        /합계|sum|더하/i => "SUM",
        /개수|count|카운트/i => "COUNT",
        /최대|최댓값|max/i => "MAX",
        /최소|최솟값|min/i => "MIN",
        /조건.*합계|sumif/i => "SUMIF",
        /조건.*평균|averageif/i => "AVERAGEIF",
        /조건.*개수|countif/i => "COUNTIF",
        /찾기|검색|lookup|vlookup/i => "VLOOKUP",
        /날짜|오늘|today/i => "TODAY",
        /시간|now/i => "NOW"
      }.freeze

      def detect_formula_type(text)
        FORMULA_PATTERNS.each do |pattern, formula_type|
          return formula_type if text.match?(pattern)
        end
        nil
      end
    end
  end
end
