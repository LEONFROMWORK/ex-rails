# frozen_string_literal: true

module Api
  module V1
    class SettingsController < ApplicationController
      before_action :authenticate_api_user!

      # GET /api/v1/settings/model
      def model
        current_model = get_current_model

        render json: {
          model: current_model,
          available_models: get_available_models,
          last_updated: Time.current.iso8601
        }
      end

      # POST /api/v1/settings/model
      def update_model
        model_id = params[:model]

        if model_id.present? && valid_model?(model_id)
          set_current_model(model_id)

          render json: {
            success: true,
            model: model_id,
            message: "AI 모델이 #{model_id}로 변경되었습니다."
          }
        else
          render json: {
            success: false,
            error: "유효하지 않은 모델 ID입니다."
          }, status: 400
        end
      end

      # GET /api/v1/settings/openrouter
      def openrouter_config
        config = get_openrouter_config

        render json: config
      end

      # POST /api/v1/settings/openrouter
      def update_openrouter_config
        api_key = params[:api_key]

        if api_key.present?
          update_openrouter_api_key(api_key)

          render json: {
            success: true,
            message: "OpenRouter API 키가 업데이트되었습니다."
          }
        else
          render json: {
            success: false,
            error: "API 키가 필요합니다."
          }, status: 400
        end
      end

      private

      def get_current_model
        # Get current model from settings or environment
        # This could be stored in user preferences or system settings
        Rails.application.credentials.dig(:openai, :default_model) ||
        ENV["DEFAULT_AI_MODEL"] ||
        "anthropic/claude-3.5-sonnet"
      end

      def get_available_models
        # Return list of available models
        [
          {
            id: "openai/gpt-4o-mini",
            name: "GPT-4o Mini",
            provider: "OpenAI",
            tier: "budget"
          },
          {
            id: "openai/gpt-4o",
            name: "GPT-4o",
            provider: "OpenAI",
            tier: "premium"
          },
          {
            id: "anthropic/claude-3.5-sonnet",
            name: "Claude 3.5 Sonnet",
            provider: "Anthropic",
            tier: "balanced"
          },
          {
            id: "anthropic/claude-3-haiku",
            name: "Claude 3 Haiku",
            provider: "Anthropic",
            tier: "budget"
          },
          {
            id: "google/gemini-flash-1.5",
            name: "Gemini Flash 1.5",
            provider: "Google",
            tier: "budget"
          }
        ]
      end

      def valid_model?(model_id)
        get_available_models.any? { |model| model[:id] == model_id }
      end

      def set_current_model(model_id)
        # Store current model in user preferences or system settings
        # For now, we'll just log it
        Rails.logger.info("Setting current AI model to: #{model_id}")

        # In a real implementation, you might:
        # - Store in user preferences
        # - Store in system settings
        # - Update environment variables
        # - Store in Redis cache

        # Example: Store in Rails cache
        Rails.cache.write("current_ai_model", model_id, expires_in: 1.hour)
      end

      def get_openrouter_config
        {
          api_key_configured: openrouter_api_key_configured?,
          base_url: get_openrouter_base_url,
          timeout: get_api_timeout,
          retry_attempts: get_retry_attempts,
          rate_limit: get_rate_limit_config
        }
      end

      def openrouter_api_key_configured?
        Rails.application.credentials.dig(:openrouter, :api_key).present? ||
        ENV["OPENROUTER_API_KEY"].present?
      end

      def get_openrouter_base_url
        ENV["OPENROUTER_BASE_URL"] || "https://openrouter.ai/api/v1"
      end

      def get_api_timeout
        (ENV["AI_API_TIMEOUT"] || 30).to_i
      end

      def get_retry_attempts
        (ENV["AI_API_RETRY_ATTEMPTS"] || 3).to_i
      end

      def get_rate_limit_config
        {
          requests_per_minute: (ENV["AI_RATE_LIMIT_RPM"] || 100).to_i,
          tokens_per_minute: (ENV["AI_RATE_LIMIT_TPM"] || 10000).to_i
        }
      end

      def update_openrouter_api_key(api_key)
        # In a real implementation, you would:
        # - Validate the API key
        # - Store it securely (encrypted)
        # - Update credentials or environment

        Rails.logger.info("Updating OpenRouter API key")

        # For now, just cache it
        Rails.cache.write("openrouter_api_key", api_key, expires_in: 1.hour)
      end

      def authenticate_api_user!
        # For now, allow all requests
        # In production, implement proper API authentication
        true
      end
    end
  end
end
