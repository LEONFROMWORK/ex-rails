# frozen_string_literal: true

module Infrastructure
  module AiProviders
    class AnthropicProvider < BaseProvider
      API_URL = "https://api.anthropic.com/v1/messages"

      def initialize
        @api_key = ENV["ANTHROPIC_API_KEY"] || ENV["OPENROUTER_API_KEY"]
        raise "Anthropic API key not configured" unless @api_key.present?
      end

      def generate_response(prompt:, max_tokens: 1000, temperature: 0.7, model: nil)
        model ||= "claude-3-haiku-20240307"

        with_retries do
          response = make_request(
            model: model,
            messages: [ { role: "user", content: prompt } ],
            max_tokens: max_tokens,
            temperature: temperature
          )

          if response.success?
            parse_response(response)
          else
            error_message = response.parsed_response.dig("error", "message") || "Unknown error"
            handle_api_error(StandardError.new(error_message), "Anthropic")
          end
        end
      rescue StandardError => e
        handle_api_error(e, "Anthropic")
      end

      private

      def make_request(params)
        HTTParty.post(
          API_URL,
          headers: {
            "x-api-key" => @api_key,
            "anthropic-version" => "2023-06-01",
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
          content: data.dig("content", 0, "text"),
          usage: {
            prompt_tokens: data.dig("usage", "input_tokens"),
            completion_tokens: data.dig("usage", "output_tokens"),
            total_tokens: (data.dig("usage", "input_tokens") || 0) + (data.dig("usage", "output_tokens") || 0)
          },
          model: data["model"],
          finish_reason: data["stop_reason"]
        }

        if validate_response(result)
          Common::Result.success(result)
        else
          Common::Result.failure("Invalid response format from Anthropic")
        end
      end
    end
  end
end
