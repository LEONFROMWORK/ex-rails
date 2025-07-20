# frozen_string_literal: true

module AiIntegration
  module Factories
    # Factory for creating AI providers
    # Follows Factory Pattern and Open/Closed Principle (OCP)
    class ProviderFactory
      PROVIDERS = {
        openrouter: AiIntegration::Providers::OpenrouterProvider,
        anthropic: AiIntegration::Providers::AnthropicProvider,
        openai: AiIntegration::Providers::OpenaiProvider
      }.freeze

      def create_provider(provider_type, tier: :cost_effective, **options)
        provider_class = PROVIDERS[provider_type.to_sym]
        raise ArgumentError, "Unknown provider: #{provider_type}" unless provider_class

        provider_class.new(tier: tier, **options)
      end

      def create_multimodal_provider(tier = :cost_effective)
        # OpenRouter supports multimodal for all tiers
        create_provider(:openrouter, tier: tier)
      end

      def create_text_provider(tier = :cost_effective)
        # Use the most cost-effective provider for text
        create_provider(:openrouter, tier: tier)
      end

      def available_providers
        PROVIDERS.keys
      end

      # Extension point for new providers (Open/Closed Principle)
      def register_provider(name, provider_class)
        unless provider_class.include?(AiIntegration::Contracts::AiProvider)
          raise ArgumentError, "Provider must include AiIntegration::Contracts::AiProvider"
        end

        PROVIDERS[name.to_sym] = provider_class
      end
    end
  end
end
