# frozen_string_literal: true

module Infrastructure
  module AiProviders
    class OpenRouterProvider < BaseProvider
      API_BASE_URL = "https://openrouter.ai/api/v1"

      # Model configurations for 3-tier system
      TIER_MODELS = {
        "tier1" => {
          model: "mistralai/mistral-7b-instruct",
          name: "Mistral Small 3.1",
          input_price: 0.00015,  # $0.15 per 1M tokens
          output_price: 0.00015,
          max_tokens: 4000,
          quality_threshold: 0.75
        },
        "tier2" => {
          model: "meta-llama/llama-3.1-70b-instruct",
          name: "Llama 4 Maverick",
          input_price: 0.00039,  # $0.39 per 1M tokens
          output_price: 0.00039,
          max_tokens: 8000,
          quality_threshold: 0.85
        },
        "tier3" => {
          model: "openai/gpt-4o-mini",
          name: "GPT-4.1 Mini",
          input_price: 0.00040,  # $0.40 per 1M tokens
          output_price: 0.00160,  # $1.60 per 1M tokens
          max_tokens: 16000,
          quality_threshold: 0.95
        }
      }.freeze

      def initialize
        super
        @http_client = HTTParty
      end

      def generate_response(prompt:, max_tokens: 1000, temperature: 0.7, model: nil, tier: "tier1", images: nil)
        tier = tier.to_s
        model_config = TIER_MODELS[tier]

        unless model_config
          return Common::Result.failure(
            Common::Errors::AIProviderError.new(
              provider: "openrouter",
              message: "Invalid tier: #{tier}. Valid tiers: #{TIER_MODELS.keys.join(', ')}"
            )
          )
        end

        # Use tier-specific model if no model specified
        selected_model = model || model_config[:model]

        # Estimate tokens for rate limiting
        estimated_tokens = estimate_tokens(prompt)
        check_rate_limits(estimated_tokens)

        Rails.logger.info("OpenRouter API request - Model: #{selected_model}, Tier: #{tier}, Estimated tokens: #{estimated_tokens}")

        with_retries do
          make_api_request(
            prompt: prompt,
            model: selected_model,
            max_tokens: [ max_tokens, model_config[:max_tokens] ].min,
            temperature: temperature,
            images: images,
            tier: tier
          )
        end
      end

      def get_model_for_tier(tier)
        TIER_MODELS[tier.to_s]
      end

      def get_tier_models
        TIER_MODELS
      end

      def calculate_cost(input_tokens, output_tokens, tier)
        model_config = TIER_MODELS[tier.to_s]
        return 0.0 unless model_config

        input_cost = (input_tokens / 1_000_000.0) * model_config[:input_price]
        output_cost = (output_tokens / 1_000_000.0) * model_config[:output_price]

        input_cost + output_cost
      end

      private

      def make_api_request(prompt:, model:, max_tokens:, temperature:, images: nil, tier: "tier1")
        request_body = build_request_body(prompt, model, max_tokens, temperature, images)

        response = @http_client.post(
          "#{API_BASE_URL}/chat/completions",
          headers: build_headers,
          body: request_body.to_json,
          timeout: 60
        )

        if response.success?
          result = parse_successful_response(response.parsed_response, tier)
          record_api_usage(result.value[:usage][:total_tokens])
          result
        else
          handle_api_error_response(response)
        end
      rescue StandardError => e
        handle_api_error(e, "openrouter")
      end

      def build_request_body(prompt, model, max_tokens, temperature, images = nil)
        messages = []

        if images&.any?
          # Handle multimodal request
          content = [ { type: "text", text: prompt } ]

          images.each do |image|
            if image.start_with?("data:image/")
              content << {
                type: "image_url",
                image_url: { url: image }
              }
            elsif image.start_with?("http")
              content << {
                type: "image_url",
                image_url: { url: image }
              }
            else
              # File path - convert to base64
              content << {
                type: "image_url",
                image_url: { url: encode_image_file(image) }
              }
            end
          end

          messages << {
            role: "user",
            content: content
          }
        else
          # Text-only request
          messages << {
            role: "user",
            content: prompt
          }
        end

        {
          model: model,
          messages: messages,
          max_tokens: max_tokens,
          temperature: temperature,
          top_p: 1.0,
          frequency_penalty: 0.0,
          presence_penalty: 0.0,
          stream: false
        }
      end

      def encode_image_file(file_path)
        return nil unless File.exist?(file_path)

        file_extension = File.extname(file_path).downcase
        mime_type = case file_extension
        when ".png" then "image/png"
        when ".jpg", ".jpeg" then "image/jpeg"
        when ".webp" then "image/webp"
        when ".gif" then "image/gif"
        else "image/jpeg"
        end

        encoded_image = Base64.strict_encode64(File.read(file_path))
        "data:#{mime_type};base64,#{encoded_image}"
      end

      def build_headers
        {
          "Authorization" => "Bearer #{@config[:api_key]}",
          "Content-Type" => "application/json",
          "HTTP-Referer" => "https://excelapp.com",
          "X-Title" => "ExcelApp SaaS"
        }
      end

      def parse_successful_response(response, tier)
        choice = response.dig("choices", 0)
        usage = response["usage"]

        unless choice && usage
          return Common::Result.failure(
            Common::Errors::AIProviderError.new(
              provider: "openrouter",
              message: "Invalid response format from OpenRouter API"
            )
          )
        end

        # Calculate cost
        input_tokens = usage["prompt_tokens"] || 0
        output_tokens = usage["completion_tokens"] || 0
        cost = calculate_cost(input_tokens, output_tokens, tier)

        result = {
          content: choice.dig("message", "content"),
          usage: {
            prompt_tokens: input_tokens,
            completion_tokens: output_tokens,
            total_tokens: usage["total_tokens"] || (input_tokens + output_tokens)
          },
          model: response["model"],
          tier: tier,
          cost: cost,
          provider: "openrouter",
          model_config: TIER_MODELS[tier],
          raw_response: response
        }

        unless validate_response(result)
          return Common::Result.failure(
            Common::Errors::AIProviderError.new(
              provider: "openrouter",
              message: "Invalid response content"
            )
          )
        end

        Common::Result.success(result)
      end

      def handle_api_error_response(response)
        error_message = response.parsed_response&.dig("error", "message") || "Unknown API error"

        Rails.logger.error("OpenRouter API error (#{response.code}): #{error_message}")

        Common::Result.failure(
          Common::Errors::AIProviderError.new(
            provider: "openrouter",
            message: "API error (#{response.code}): #{error_message}",
            details: {
              status_code: response.code,
              response_body: response.body
            }
          )
        )
      end

      def estimate_tokens(text)
        # Rough estimation: 1 token ≈ 4 characters
        (text.length / 4.0).ceil
      end

      def validate_configuration
        unless @config[:api_key].present?
          raise "OpenRouter API key not configured. Please set OPENROUTER_API_KEY environment variable."
        end
      end
    end
  end
end
