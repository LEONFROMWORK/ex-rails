# frozen_string_literal: true

module AiIntegration
  module MultiProvider
    class ChatService
      attr_reader :provider

      PROVIDERS = {
        "openai" => Infrastructure::AiProviders::OpenAiProvider,
        "anthropic" => Infrastructure::AiProviders::AnthropicProvider,
        "google" => Infrastructure::AiProviders::GoogleProvider
      }.freeze

      SYSTEM_PROMPT = <<~PROMPT
        You are an AI assistant specialized in Excel and spreadsheet management.#{' '}
        You can help users with:
        - Creating Excel formulas and functions
        - Analyzing spreadsheet errors
        - Generating Excel file templates
        - Optimizing spreadsheet performance
        - Data analysis and visualization recommendations

        When users ask you to create or generate Excel content, provide clear,#{' '}
        structured responses that can be easily implemented in Excel.
      PROMPT

      def initialize(provider: "openai")
        @provider = provider
        @client = PROVIDERS[provider]&.new
        raise ArgumentError, "Unknown provider: #{provider}" unless @client
      end

      def generate_response(message:, context: [], file_context: nil)
        messages = build_messages(message, context, file_context)

        response = @client.generate_response(
          prompt: format_messages(messages),
          max_tokens: 1500,
          temperature: 0.7,
          model: default_model
        )

        if response.success?
          parse_response(response.value)
        else
          response
        end
      rescue StandardError => e
        Rails.logger.error("Chat service failed: #{e.message}")
        Common::Result.failure(
          Common::Errors::AIProviderError.new(
            provider: provider,
            message: e.message
          )
        )
      end

      private

      def build_messages(message, context, file_context)
        messages = []

        # Add system prompt
        messages << { role: "system", content: SYSTEM_PROMPT }

        # Add file context if available
        if file_context
          messages << {
            role: "system",
            content: "User is working with an Excel file: #{file_context.to_json}"
          }
        end

        # Add conversation context
        messages.concat(context) if context.present?

        # Add current message
        messages << { role: "user", content: message }

        messages
      end

      def format_messages(messages)
        if provider == "openai" || provider == "anthropic"
          # These providers support structured message format
          messages.to_json
        else
          # For other providers, concatenate messages
          messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
        end
      end

      def default_model
        case provider
        when "openai"
          "gpt-3.5-turbo"
        when "anthropic"
          "claude-3-haiku-20240307"
        when "google"
          "gemini-pro"
        else
          "gpt-3.5-turbo"
        end
      end

      def parse_response(response)
        Common::Result.success({
          content: response[:content],
          credits_used: response[:usage][:total_tokens],
          model: response[:model]
        })
      end
    end
  end
end
