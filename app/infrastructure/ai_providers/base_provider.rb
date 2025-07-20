# frozen_string_literal: true

module Infrastructure
  module AiProviders
    class BaseProvider
      MAX_RETRIES = 3
      RETRY_DELAY = 1.0

      def initialize
        @provider_name = self.class.name.demodulize.underscore.gsub("_provider", "")
        @config = ProviderConfig.get_provider_config(@provider_name)
        @rate_limiter = RateLimiter.new(@provider_name)

        validate_configuration
      end

      def generate_response(prompt:, max_tokens: 1000, temperature: 0.7, model: nil)
        raise NotImplementedError, "#{self.class} must implement #generate_response"
      end

      def available?
        @config[:api_key].present?
      end

      def health_check
        return { status: "unavailable", reason: "No API key configured" } unless available?

        begin
          # Simple health check request
          test_response = generate_response(
            prompt: "Test",
            max_tokens: 10,
            temperature: 0.1
          )

          if test_response.success?
            {
              status: "healthy",
              provider: @provider_name,
              rate_limit_status: @rate_limiter.get_current_usage
            }
          else
            {
              status: "unhealthy",
              provider: @provider_name,
              error: test_response.error.message
            }
          end
        rescue StandardError => e
          {
            status: "unhealthy",
            provider: @provider_name,
            error: e.message
          }
        end
      end

      protected

      def validate_configuration
        unless @config[:api_key].present?
          raise "#{@provider_name.humanize} API key not configured"
        end
      end

      def check_rate_limits(estimated_tokens)
        unless @rate_limiter.can_make_request?
          wait_time = @rate_limiter.wait_time_until_available
          raise StandardError, "Rate limit exceeded. Try again in #{wait_time} seconds."
        end

        unless @rate_limiter.can_use_tokens?(estimated_tokens)
          raise StandardError, "Token rate limit exceeded. Try again later."
        end
      end

      def record_api_usage(credits_used)
        @rate_limiter.record_request(credits_used)
      end

      def with_retries(max_retries: MAX_RETRIES, &block)
        retries = 0
        begin
          block.call
        rescue StandardError => e
          retries += 1
          if retries <= max_retries && retryable_error?(e)
            Rails.logger.warn("#{self.class.name} API error (retry #{retries}/#{max_retries}): #{e.message}")
            sleep(RETRY_DELAY * retries)
            retry
          else
            raise e
          end
        end
      end

      def retryable_error?(error)
        return true if error.is_a?(Net::TimeoutError)
        return true if error.is_a?(Errno::ECONNRESET)
        return true if error.is_a?(SocketError)

        # HTTP-specific retryable errors
        if error.respond_to?(:response) && error.response
          status = error.response.code.to_i
          return true if [ 429, 500, 502, 503, 504 ].include?(status)
        end

        false
      end

      def handle_api_error(error, provider_name)
        Rails.logger.error("#{provider_name} API error: #{error.message}")

        Common::Result.failure(
          Common::Errors::AIProviderError.new(
            provider: provider_name,
            message: error.message,
            details: { error_class: error.class.name }
          )
        )
      end

      def validate_response(response)
        return false unless response.is_a?(Hash)
        return false unless response[:content].present?
        return false unless response[:usage].is_a?(Hash)

        true
      end
    end
  end
end
