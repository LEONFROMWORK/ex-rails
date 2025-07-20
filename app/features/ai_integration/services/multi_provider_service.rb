# frozen_string_literal: true

module AiIntegration
  module Services
    class MultiProviderService
      TIER1_MODELS = {
        openrouter: [ "mistralai/mistral-small-2409" ]
      }.freeze

      TIER2_MODELS = {
        openrouter: [ "meta-llama/llama-3.2-405b-instruct" ]
      }.freeze

      TIER3_MODELS = {
        openrouter: [ "openai/gpt-4o-mini-2024-07-18" ]
      }.freeze

      def initialize(tier: 1)
        @tier = tier
        @models = case tier
        when 3
                    TIER3_MODELS
        when 2
                    TIER2_MODELS
        else
                    TIER1_MODELS
        end
        @cache = AiIntegration::Services::AiResponseCache.new
        @validator = AiIntegration::ResponseValidation::AiResponseValidator
      end

      def chat(message:, context: {}, previous_response: nil, user:)
        prompt = build_prompt(message, context, previous_response)

        # Check cache first
        cache_key = @cache.generate_cache_key(
          type: :chat,
          content: prompt,
          provider: "multi",
          user_tier: @tier
        )

        cached_response = @cache.get(cache_key)
        if cached_response
          return cached_response["data"]
        end

        # Try providers in order of preference
        @models.each do |provider, models|
          models.each do |model|
            begin
              response = send_request(provider, model, prompt, user)
              if response
                parsed_response = parse_response(response, provider, model)

                # Validate response
                validation_result = @validator.new(parsed_response, expected_type: :chat).validate
                if validation_result.success?
                  # Cache valid response
                  @cache.set(cache_key, validation_result.value)
                  return validation_result.value
                else
                  Rails.logger.warn("Invalid AI response from #{provider}/#{model}: #{validation_result.error}")
                  next
                end
              end
            rescue => e
              Rails.logger.warn("AI Provider #{provider}/#{model} failed: #{e.message}")
              next
            end
          end
        end

        raise "All AI providers failed or returned invalid responses"
      end

      def analyze_excel(file_data:, user:, errors: [])
        prompt = build_excel_analysis_prompt(file_data, errors)

        # Check cache first
        cache_key = @cache.generate_cache_key(
          type: :excel_analysis,
          content: prompt,
          provider: "multi",
          user_tier: @tier
        )

        cached_response = @cache.get(cache_key)
        if cached_response
          return cached_response["data"]
        end

        @models.each do |provider, models|
          models.each do |model|
            begin
              response = send_request(provider, model, prompt, user)
              if response
                parsed_response = parse_analysis_response(response, provider, model)

                # Validate response
                validation_result = @validator.new(parsed_response, expected_type: :excel_analysis).validate
                if validation_result.success?
                  # Cache valid response
                  @cache.set(cache_key, validation_result.value)
                  return validation_result.value
                else
                  Rails.logger.warn("Invalid AI response from #{provider}/#{model}: #{validation_result.error}")
                  next
                end
              end
            rescue => e
              Rails.logger.warn("AI Provider #{provider}/#{model} failed: #{e.message}")
              next
            end
          end
        end

        raise "All AI providers failed or returned invalid responses for Excel analysis"
      end

      private

      def build_prompt(message, context, previous_response)
        prompt = []

        # System prompt
        prompt << {
          role: "system",
          content: excel_expert_system_prompt
        }

        # Add context if available
        if context[:file_info]
          prompt << {
            role: "system",
            content: "File context: #{context[:file_info].to_json}"
          }
        end

        # Add conversation history
        if context[:conversation_history]&.any?
          context[:conversation_history].each do |msg|
            prompt << {
              role: msg[:role],
              content: msg[:content]
            }
          end
        end

        # Add previous tier 1 response if this is tier 2
        if previous_response
          prompt << {
            role: "system",
            content: "Previous analysis (please improve): #{previous_response}"
          }
        end

        # User message
        prompt << {
          role: "user",
          content: message
        }

        prompt
      end

      def build_excel_analysis_prompt(file_data, errors)
        [
          {
            role: "system",
            content: excel_analysis_system_prompt
          },
          {
            role: "user",
            content: {
              file_name: file_data[:name],
              file_size: file_data[:size],
              detected_errors: errors,
              request: "Please analyze the detected errors and provide solutions"
            }.to_json
          }
        ]
      end

      def excel_expert_system_prompt
        <<~PROMPT
          You are an Excel expert AI assistant for ExcelApp, a platform that helps users identify and fix Excel errors.

          Your capabilities:
          - Analyze Excel formulas, functions, and data validation errors
          - Provide step-by-step solutions for Excel problems
          - Generate optimized Excel formulas and functions
          - Recommend best practices for spreadsheet management

          Guidelines:
          - Be concise but thorough in your explanations
          - Always provide practical, actionable advice
          - Use Korean for Korean users, English for others
          - Include confidence scores in your responses when possible
          - Reference specific cells, ranges, or functions when applicable
        PROMPT
      end

      def excel_analysis_system_prompt
        <<~PROMPT
          You are an advanced Excel analysis AI. Analyze the provided Excel file data and errors, then provide:

          1. Error categorization and severity assessment
          2. Root cause analysis for each error
          3. Step-by-step fix instructions
          4. Prevention recommendations
          5. Performance optimization suggestions

          Respond in JSON format with structured analysis results.
        PROMPT
      end

      def send_request(provider, model, prompt, user)
        case provider
        when :openrouter
          send_openrouter_request(model, prompt, user)
        when :openai
          send_openai_request(model, prompt, user)
        when :anthropic
          send_anthropic_request(model, prompt, user)
        else
          raise "Unknown provider: #{provider}"
        end
      end

      def send_openrouter_request(model, prompt, user)
        response = HTTParty.post(
          "https://openrouter.ai/api/v1/chat/completions",
          headers: {
            "Authorization" => "Bearer #{ENV['OPENROUTER_API_KEY']}",
            "Content-Type" => "application/json",
            "HTTP-Referer" => "https://excelapp.ai",
            "X-Title" => "ExcelApp AI"
          },
          body: {
            model: model,
            messages: prompt,
            max_tokens: @tier == 2 ? 2000 : 1000,
            temperature: 0.7
          }.to_json
        )

        return nil unless response.success?

        JSON.parse(response.body)
      rescue => e
        Rails.logger.error("OpenRouter API error: #{e.message}")
        nil
      end

      def send_openai_request(model, prompt, user)
        response = HTTParty.post(
          "https://api.openai.com/v1/chat/completions",
          headers: {
            "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
            "Content-Type" => "application/json"
          },
          body: {
            model: model,
            messages: prompt,
            max_tokens: @tier == 2 ? 2000 : 1000,
            temperature: 0.7
          }.to_json
        )

        return nil unless response.success?

        JSON.parse(response.body)
      rescue => e
        Rails.logger.error("OpenAI API error: #{e.message}")
        nil
      end

      def send_anthropic_request(model, prompt, user)
        response = HTTParty.post(
          "https://api.anthropic.com/v1/messages",
          headers: {
            "x-api-key" => ENV["ANTHROPIC_API_KEY"],
            "Content-Type" => "application/json",
            "anthropic-version" => "2023-06-01"
          },
          body: {
            model: model,
            messages: prompt,
            max_tokens: @tier == 2 ? 2000 : 1000
          }.to_json
        )

        return nil unless response.success?

        JSON.parse(response.body)
      rescue => e
        Rails.logger.error("Anthropic API error: #{e.message}")
        nil
      end

      def parse_response(response, provider, model)
        case provider
        when :openrouter, :openai
          parse_openai_format_response(response, provider, model)
        when :anthropic
          parse_anthropic_format_response(response, provider, model)
        end
      end

      def parse_analysis_response(response, provider, model)
        parsed = parse_response(response, provider, model)

        # Try to parse as JSON for structured analysis
        begin
          analysis_data = JSON.parse(parsed[:message])
          parsed.merge(structured_analysis: analysis_data)
        rescue JSON::ParserError
          parsed
        end
      end

      def parse_openai_format_response(response, provider, model)
        choice = response.dig("choices", 0)
        usage = response["usage"]

        {
          message: choice.dig("message", "content"),
          provider: "#{provider}/#{model}",
          credits_used: calculate_credits_used(usage),
          confidence_score: extract_confidence_score(choice.dig("message", "content"))
        }
      end

      def parse_anthropic_format_response(response, provider, model)
        content = response.dig("content", 0, "text")
        usage = response["usage"]

        {
          message: content,
          provider: "#{provider}/#{model}",
          credits_used: calculate_credits_used(usage),
          confidence_score: extract_confidence_score(content)
        }
      end

      def calculate_credits_used(usage)
        if usage
          (usage["prompt_tokens"] || 0) + (usage["completion_tokens"] || 0)
        else
          @tier == 2 ? 50 : 5 # Fallback estimates
        end
      end

      def extract_confidence_score(content)
        # Try to extract confidence score from response
        if content&.match(/confidence[:\s]*(\d+(?:\.\d+)?)/i)
          $1.to_f / 100.0
        else
          @tier == 2 ? 0.9 : 0.7 # Default confidence by tier
        end
      end
    end
  end
end
