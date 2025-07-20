# frozen_string_literal: true

module Infrastructure
  module AiProviders
    class RateLimiter
      def initialize(provider_name)
        @provider_name = provider_name
        @config = ProviderConfig.get_rate_limits(provider_name)
        @cache_key_prefix = "ai_rate_limit:#{provider_name}"
      end

      def can_make_request?
        return true if @config.empty?

        current_minute = Time.current.beginning_of_minute
        cache_key = "#{@cache_key_prefix}:#{current_minute.to_i}"

        current_count = Rails.cache.fetch(cache_key, expires_in: 1.minute) { 0 }
        max_requests = @config[:requests_per_minute] || Float::INFINITY

        current_count < max_requests
      end

      def can_use_tokens?(token_count)
        return true if @config.empty?

        current_minute = Time.current.beginning_of_minute
        cache_key = "#{@cache_key_prefix}:credits:#{current_minute.to_i}"

        current_tokens = Rails.cache.fetch(cache_key, expires_in: 1.minute) { 0 }
        max_tokens = @config[:credits_per_minute] || Float::INFINITY

        (current_tokens + token_count) <= max_tokens
      end

      def record_request(token_count = 0)
        return unless @config.present?

        current_minute = Time.current.beginning_of_minute

        # Record request count
        request_cache_key = "#{@cache_key_prefix}:#{current_minute.to_i}"
        Rails.cache.increment(request_cache_key, 1, expires_in: 1.minute, initial: 0)

        # Record token usage
        if token_count > 0
          token_cache_key = "#{@cache_key_prefix}:credits:#{current_minute.to_i}"
          Rails.cache.increment(token_cache_key, token_count, expires_in: 1.minute, initial: 0)
        end
      end

      def get_current_usage
        current_minute = Time.current.beginning_of_minute

        request_cache_key = "#{@cache_key_prefix}:#{current_minute.to_i}"
        token_cache_key = "#{@cache_key_prefix}:credits:#{current_minute.to_i}"

        {
          requests: Rails.cache.read(request_cache_key) || 0,
          tokens: Rails.cache.read(token_cache_key) || 0,
          max_requests: @config[:requests_per_minute] || Float::INFINITY,
          max_tokens: @config[:credits_per_minute] || Float::INFINITY
        }
      end

      def wait_time_until_available
        return 0 if can_make_request?

        # Calculate seconds until next minute
        current_time = Time.current
        next_minute = current_time.beginning_of_minute + 1.minute

        (next_minute - current_time).to_i
      end
    end
  end
end
