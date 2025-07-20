# frozen_string_literal: true

module AiIntegration
  module MultiProvider
    class ProviderManager
      attr_reader :providers, :current_provider

      DEFAULT_FALLBACK_ORDER = [ "openrouter", "openai", "anthropic", "google" ].freeze

      def initialize(primary_provider: "openrouter", fallback_order: DEFAULT_FALLBACK_ORDER)
        @primary_provider = primary_provider
        @fallback_order = fallback_order & Infrastructure::AiProviders::ProviderConfig.available_providers.map(&:to_s)
        @current_provider = primary_provider
        @providers = {}

        initialize_providers
      end

      def generate_response(prompt:, max_tokens: 1000, temperature: 0.7, model: nil, tier: "tier1", images: nil)
        @fallback_order.each do |provider_name|
          next unless provider_available?(provider_name)

          begin
            @current_provider = provider_name
            provider = get_provider(provider_name)

            Rails.logger.info("Attempting AI request with provider: #{provider_name}, tier: #{tier}")

            # Build request parameters
            request_params = {
              prompt: prompt,
              max_tokens: max_tokens,
              temperature: temperature,
              tier: tier
            }

            # Add model if specified, otherwise use tier-specific model
            if model
              request_params[:model] = model
            else
              request_params[:model] = select_model_for_provider(provider_name, tier)
            end

            # Add images for multimodal providers
            if images&.any? && supports_multimodal?(provider_name)
              request_params[:images] = images
            end

            result = provider.generate_response(**request_params)

            if result.success?
              Rails.logger.info("Successfully generated response with #{provider_name} (tier: #{tier})")
              return result
            else
              Rails.logger.warn("Provider #{provider_name} failed: #{result.error}")
              next
            end

          rescue StandardError => e
            Rails.logger.error("Provider #{provider_name} error: #{e.message}")
            next
          end
        end

        Common::Result.failure(
          Common::Errors::AIProviderError.new(
            provider: "all",
            message: "All AI providers failed"
          )
        )
      end

      def provider_available?(provider_name)
        Infrastructure::AiProviders::ProviderConfig.available_providers.include?(provider_name.to_sym)
      end

      def get_provider(provider_name)
        @providers[provider_name] ||= create_provider(provider_name)
      end

      def reset_to_primary
        @current_provider = @primary_provider
      end

      def provider_status
        @fallback_order.map do |provider_name|
          {
            name: provider_name,
            available: provider_available?(provider_name),
            current: provider_name == @current_provider
          }
        end
      end

      private

      def initialize_providers
        @fallback_order.each do |provider_name|
          next unless provider_available?(provider_name)

          begin
            @providers[provider_name] = create_provider(provider_name)
          rescue StandardError => e
            Rails.logger.warn("Failed to initialize #{provider_name} provider: #{e.message}")
          end
        end
      end

      def create_provider(provider_name)
        case provider_name
        when "openrouter"
          Infrastructure::AiProviders::OpenRouterProvider.new
        when "openai"
          Infrastructure::AiProviders::OpenAiProvider.new
        when "anthropic"
          Infrastructure::AiProviders::AnthropicProvider.new
        when "google"
          Infrastructure::AiProviders::GoogleProvider.new
        else
          raise ArgumentError, "Unknown provider: #{provider_name}"
        end
      end

      def select_model_for_provider(provider_name, tier)
        Infrastructure::AiProviders::ProviderConfig.get_model_for_tier(provider_name, tier)
      end

      def supports_multimodal?(provider_name)
        # OpenRouter and OpenAI support multimodal
        [ "openrouter", "openai" ].include?(provider_name)
      end
    end
  end
end
