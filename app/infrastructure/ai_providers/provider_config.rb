# frozen_string_literal: true

module Infrastructure
  module AiProviders
    class ProviderConfig
      def self.load_config
        @config ||= {
          openrouter: {
            api_key: ENV["OPENROUTER_API_KEY"],
            base_url: ENV["OPENROUTER_BASE_URL"] || "https://openrouter.ai/api/v1",
            models: {
              tier1: ENV["OPENROUTER_TIER1_MODEL"] || "mistralai/mistral-7b-instruct",
              tier2: ENV["OPENROUTER_TIER2_MODEL"] || "meta-llama/llama-3.1-70b-instruct",
              tier3: ENV["OPENROUTER_TIER3_MODEL"] || "openai/gpt-4o-mini"
            },
            rate_limits: {
              requests_per_minute: 5000,
              tokens_per_minute: 500_000
            }
          },
          openai: {
            api_key: ENV["OPENAI_API_KEY"] || ENV["OPENROUTER_API_KEY"],
            base_url: ENV["OPENAI_BASE_URL"] || "https://api.openai.com/v1",
            models: {
              tier1: ENV["OPENAI_TIER1_MODEL"] || "gpt-3.5-turbo",
              tier2: ENV["OPENAI_TIER2_MODEL"] || "gpt-4"
            },
            rate_limits: {
              requests_per_minute: 3000,
              tokens_per_minute: 250_000
            }
          },
          anthropic: {
            api_key: ENV["ANTHROPIC_API_KEY"] || ENV["OPENROUTER_API_KEY"],
            base_url: ENV["ANTHROPIC_BASE_URL"] || "https://api.anthropic.com/v1",
            models: {
              tier1: ENV["ANTHROPIC_TIER1_MODEL"] || "claude-3-haiku-20240307",
              tier2: ENV["ANTHROPIC_TIER2_MODEL"] || "claude-3-opus-20240229"
            },
            rate_limits: {
              requests_per_minute: 1000,
              tokens_per_minute: 200_000
            }
          },
          google: {
            api_key: ENV["GOOGLE_API_KEY"],
            base_url: ENV["GOOGLE_BASE_URL"] || "https://generativelanguage.googleapis.com/v1",
            models: {
              tier1: ENV["GOOGLE_TIER1_MODEL"] || "gemini-pro",
              tier2: ENV["GOOGLE_TIER2_MODEL"] || "gemini-pro"
            },
            rate_limits: {
              requests_per_minute: 1500,
              tokens_per_minute: 300_000
            }
          }
        }
      end

      def self.get_provider_config(provider_name)
        config = load_config
        config[provider_name.to_sym] || {}
      end

      def self.available_providers
        load_config.keys.select do |provider|
          provider_config = get_provider_config(provider)
          provider_config[:api_key].present?
        end
      end

      def self.get_model_for_tier(provider_name, tier)
        config = get_provider_config(provider_name)
        tier_sym = tier.to_sym

        # Return exact tier model if available
        return config.dig(:models, tier_sym) if config.dig(:models, tier_sym)

        # Fallback logic for missing tiers
        case tier
        when "tier3"
          config.dig(:models, :tier2) || config.dig(:models, :tier1)
        when "tier2"
          config.dig(:models, :tier1)
        else
          config.dig(:models, :tier1)
        end
      end

      def self.get_rate_limits(provider_name)
        config = get_provider_config(provider_name)
        config[:rate_limits] || {}
      end

      def self.validate_configuration!
        missing_configs = []

        available_providers.each do |provider|
          config = get_provider_config(provider)

          unless config[:api_key].present?
            missing_configs << "#{provider.upcase}_API_KEY"
          end

          unless config[:models][:tier1].present?
            missing_configs << "#{provider.upcase}_TIER1_MODEL"
          end
        end

        if missing_configs.any?
          Rails.logger.warn("Missing AI provider configurations: #{missing_configs.join(', ')}")
        end

        if available_providers.empty?
          raise StandardError, "No AI providers configured. Please set API keys."
        end

        Rails.logger.info("AI Providers configured: #{available_providers.join(', ')}")
      end
    end
  end
end
