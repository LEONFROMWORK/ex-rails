# frozen_string_literal: true

module Infrastructure
  module AiProviders
    class OpenAiProvider < BaseProvider
      def generate_response(prompt:, max_tokens: 1000, temperature: 0.7, model: nil)
        model ||= ProviderConfig.get_model_for_tier(@provider_name, "tier1")

        # Check rate limits before making request
        check_rate_limits(max_tokens)

        with_retries do
          response = make_request(
            model: model,
            messages: [ { role: "user", content: prompt } ],
            max_tokens: max_tokens,
            temperature: temperature
          )

          if response.success?
            result = parse_response(response)

            # Record usage for rate limiting
            if result.success?
              record_api_usage(result.value[:usage][:total_tokens])
            end

            result
          else
            error_message = response.parsed_response.dig("error", "message") || "Unknown error"
            handle_api_error(StandardError.new(error_message), "OpenAI")
          end
        end
      rescue StandardError => e
        handle_api_error(e, "OpenAI")
      end

      private

      def make_request(params)
        api_url = "#{@config[:base_url]}/chat/completions"

        HTTParty.post(
          api_url,
          headers: {
            "Authorization" => "Bearer #{@config[:api_key]}",
            "Content-Type" => "application/json",
            "User-Agent" => "ExcelApp-Rails/1.0"
          },
          body: params.to_json,
          timeout: 60,
          open_timeout: 10
        )
      end

      def parse_response(response)
        data = response.parsed_response

        result = {
          content: data.dig("choices", 0, "message", "content"),
          usage: {
            prompt_tokens: data.dig("usage", "prompt_tokens"),
            completion_tokens: data.dig("usage", "completion_tokens"),
            total_tokens: data.dig("usage", "total_tokens")
          },
          model: data["model"],
          finish_reason: data.dig("choices", 0, "finish_reason")
        }

        if validate_response(result)
          Common::Result.success(result)
        else
          Common::Result.failure("Invalid response format from OpenAI")
        end
      end
    end
  end
end
