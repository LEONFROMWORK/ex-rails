# frozen_string_literal: true

module AiIntegration
  module Providers
    # OpenRouter AI provider implementation
    # Follows Single Responsibility Principle (SRP) and Liskov Substitution Principle (LSP)
    class OpenrouterProvider
      include AiIntegration::Contracts::AiProvider
      include HTTParty

      base_uri "https://openrouter.ai/api/v1"

      MODELS = {
        cost_effective: {
          text: "google/gemini-flash-1.5",
          multimodal: "google/gemini-flash-1.5",
          cost_per_million_tokens: 0.075
        },
        balanced: {
          text: "anthropic/claude-3-haiku",
          multimodal: "anthropic/claude-3-haiku",
          cost_per_million_tokens: 0.25
        },
        premium: {
          text: "openai/gpt-4-turbo",
          multimodal: "openai/gpt-4-vision-preview",
          cost_per_million_tokens: 10.0
        }
      }.freeze

      def initialize(tier: :cost_effective, api_key: nil)
        @tier = tier.to_sym
        @api_key = api_key || Rails.application.credentials.openrouter_api_key
        @model_config = MODELS[@tier]
        raise ArgumentError, "Invalid tier: #{tier}" unless @model_config
      end

      def provider_name
        "openrouter"
      end

      def supported_features
        %w[text_analysis chat image_analysis conversation]
      end

      def cost_per_token
        @model_config[:cost_per_million_tokens] / 1_000_000.0
      end

      private

      def perform_analysis(prompt, context, options)
        model = @model_config[:text]
        response = make_api_request(model, build_text_messages(prompt, context), options)
        process_response(response)
      end

      def perform_chat(message, context, options)
        model = @model_config[:text]
        messages = build_chat_messages(message, context)
        response = make_api_request(model, messages, options)
        process_response(response)
      end

      def perform_image_analysis(image_data, prompt, context, options)
        model = @model_config[:multimodal]
        messages = build_multimodal_messages(image_data, prompt, context)
        response = make_api_request(model, messages, options)
        process_response(response)
      end

      def make_api_request(model, messages, options)
        request_body = {
          model: model,
          messages: messages,
          max_tokens: options[:max_tokens] || 4096,
          temperature: options[:temperature] || 0.4,
          top_p: options[:top_p] || 1.0
        }

        headers = {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{@api_key}",
          "HTTP-Referer" => Rails.application.credentials.app_url || "http://localhost:3000",
          "X-Title" => "ExcelApp AI Analysis"
        }

        response = self.class.post(
          "/chat/completions",
          headers: headers,
          body: request_body.to_json,
          timeout: 60
        )

        unless response.success?
          raise "OpenRouter API error: #{response.code} - #{response.body}"
        end

        response.parsed_response
      end

      def build_text_messages(prompt, context)
        messages = []

        if context[:system_prompt]
          messages << { role: "system", content: context[:system_prompt] }
        end

        messages << { role: "user", content: prompt }
        messages
      end

      def build_chat_messages(message, context)
        messages = []

        if context[:system_prompt]
          messages << { role: "system", content: context[:system_prompt] }
        end

        # Add conversation history if present
        if context[:conversation_history]
          context[:conversation_history].each do |msg|
            messages << { role: msg[:role], content: msg[:content] }
          end
        end

        messages << { role: "user", content: message }
        messages
      end

      def build_multimodal_messages(image_data, prompt, context)
        content = [ { type: "text", text: prompt } ]

        # Add image
        content << {
          type: "image_url",
          image_url: {
            url: "data:#{detect_image_mime_type(image_data)};base64,#{encode_image_data(image_data)}"
          }
        }

        messages = []

        if context[:system_prompt]
          messages << { role: "system", content: context[:system_prompt] }
        end

        messages << { role: "user", content: content }
        messages
      end

      def process_response(response)
        choice = response.dig("choices", 0)
        return Shared::Types::Result.failure(error: "No response generated") unless choice

        content = choice.dig("message", "content")
        usage = response["usage"] || {}

        Shared::Types::Result.success(
          value: {
            content: content,
            credits_used: usage["total_tokens"] || 0,
            prompt_tokens: usage["prompt_tokens"] || 0,
            completion_tokens: usage["completion_tokens"] || 0,
            cost: calculate_cost(usage["total_tokens"] || 0),
            provider: provider_name,
            model: @model_config[:text],
            tier: @tier
          }
        )
      end

      def detect_image_mime_type(image_data)
        return "image/jpeg" if image_data[0, 4] == "\xFF\xD8\xFF".b
        return "image/png" if image_data[0, 8] == "\x89PNG\r\n\x1A\n".b
        return "image/gif" if image_data[0, 6] == "GIF87a".b || image_data[0, 6] == "GIF89a".b
        return "image/webp" if image_data[8, 4] == "WEBP".b

        "image/jpeg" # default
      end

      def encode_image_data(image_data)
        Base64.strict_encode64(image_data)
      end

      def calculate_cost(credits_used)
        credits_used * cost_per_token
      end
    end
  end
end
