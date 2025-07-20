# frozen_string_literal: true

module Infrastructure
  module AiProviders
    class GoogleProvider < BaseProvider
      API_URL = "https://generativelanguage.googleapis.com/v1/models"

      def initialize
        @api_key = ENV["GOOGLE_API_KEY"]
        raise "Google API key not configured" unless @api_key.present?
      end

      def generate_response(prompt:, max_tokens: 1000, temperature: 0.7, model: nil)
        model ||= "gemini-pro"

        with_retries do
          response = make_request(
            model: model,
            prompt: prompt,
            max_tokens: max_tokens,
            temperature: temperature
          )

          if response.success?
            parse_response(response)
          else
            error_message = response.parsed_response.dig("error", "message") || "Unknown error"
            handle_api_error(StandardError.new(error_message), "Google")
          end
        end
      rescue StandardError => e
        handle_api_error(e, "Google")
      end

      private

      def make_request(params)
        model = params[:model]

        HTTParty.post(
          "#{API_URL}/#{model}:generateContent?key=#{@api_key}",
          headers: {
            "Content-Type" => "application/json",
            "User-Agent" => "ExcelApp-Rails/1.0"
          },
          body: {
            contents: [ {
              parts: [ {
                text: params[:prompt]
              } ]
            } ],
            generationConfig: {
              temperature: params[:temperature],
              maxOutputTokens: params[:max_tokens]
            }
          }.to_json,
          timeout: 60,
          open_timeout: 10
        )
      end

      def parse_response(response)
        data = response.parsed_response

        content = data.dig("candidates", 0, "content", "parts", 0, "text")

        # Google doesn't provide token counts in the same way
        # This is an approximation
        estimated_tokens = (content&.split(" ")&.length || 0) * 1.3

        result = {
          content: content,
          usage: {
            prompt_tokens: estimated_tokens.to_i / 2,
            completion_tokens: estimated_tokens.to_i / 2,
            total_tokens: estimated_tokens.to_i
          },
          model: "gemini-pro",
          finish_reason: data.dig("candidates", 0, "finishReason")
        }

        if validate_response(result)
          Common::Result.success(result)
        else
          Common::Result.failure("Invalid response format from Google")
        end
      end
    end
  end
end
