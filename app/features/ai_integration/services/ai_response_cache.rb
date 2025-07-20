# frozen_string_literal: true

module AiIntegration
  module Services
    class AiResponseCache
        CACHE_TTL = 1.hour.freeze
        MAX_CACHE_SIZE = 10.megabytes.freeze

        def initialize
          @cache = Rails.cache
      end

        def get(cache_key)
        cached_data = @cache.read(cache_key)
        return nil unless cached_data

        # Verify cache integrity
        if valid_cached_response?(cached_data)
          Rails.logger.info("AI cache hit for key: #{cache_key}")
          increment_cache_stats(:hits)
          cached_data
        else
          Rails.logger.warn("Invalid cached response found, removing: #{cache_key}")
          @cache.delete(cache_key)
          increment_cache_stats(:misses)
          nil
        end
    rescue => e
        Rails.logger.error("Error reading from AI cache: #{e.message}")
        increment_cache_stats(:errors)
        nil
      end

        def set(cache_key, response_data, ttl: CACHE_TTL)
        return false unless cacheable_response?(response_data)

        # Add metadata
        cached_response = {
          data: response_data,
          cached_at: Time.current.iso8601,
          expires_at: (Time.current + ttl).iso8601,
          cache_version: "1.0"
        }

        success = @cache.write(cache_key, cached_response, expires_in: ttl)

        if success
          Rails.logger.info("AI response cached with key: #{cache_key}")
          increment_cache_stats(:writes)
        else
          Rails.logger.warn("Failed to cache AI response: #{cache_key}")
          increment_cache_stats(:write_failures)
        end

        success
    rescue => e
        Rails.logger.error("Error writing to AI cache: #{e.message}")
        increment_cache_stats(:errors)
        false
      end

        def generate_cache_key(type:, content:, provider:, model: nil, user_tier: nil)
        # Create deterministic hash from content
        content_hash = Digest::SHA256.hexdigest(content.to_s.strip.downcase)

        # Include relevant parameters
        key_parts = [
          "ai_response",
          type.to_s,
          provider.to_s,
          model&.to_s,
          user_tier&.to_s,
          content_hash[0, 16] # First 16 chars of hash
        ].compact

        key_parts.join(":")
      end

        def clear_expired
        # This would be called by a background job
        pattern = "ai_response:*"
        keys = @cache.redis&.keys(pattern) || []

        expired_count = 0
        keys.each do |key|
          cached_data = @cache.read(key)
          next unless cached_data&.is_a?(Hash)

          if cached_data["expires_at"] && Time.parse(cached_data["expires_at"]) < Time.current
            @cache.delete(key)
            expired_count += 1
          end
        end

        Rails.logger.info("Cleared #{expired_count} expired AI cache entries")
        expired_count
    rescue => e
        Rails.logger.error("Error clearing expired cache: #{e.message}")
        0
      end

        def stats
        cache_stats = get_cache_stats

        {
          hits: cache_stats[:hits] || 0,
          misses: cache_stats[:misses] || 0,
          writes: cache_stats[:writes] || 0,
          write_failures: cache_stats[:write_failures] || 0,
          errors: cache_stats[:errors] || 0,
          hit_rate: calculate_hit_rate(cache_stats),
          total_keys: count_total_keys
        }
      end

        def clear_all
        pattern = "ai_response:*"
        keys = @cache.redis&.keys(pattern) || []

        deleted_count = 0
        keys.each do |key|
          if @cache.delete(key)
            deleted_count += 1
          end
        end

        reset_cache_stats
        Rails.logger.info("Cleared #{deleted_count} AI cache entries")
        deleted_count
    rescue => e
        Rails.logger.error("Error clearing all cache: #{e.message}")
        0
      end

    private

        def valid_cached_response?(cached_data)
        return false unless cached_data.is_a?(Hash)
        return false unless cached_data["data"].is_a?(Hash)
        return false unless cached_data["cached_at"]
        return false unless cached_data["expires_at"]

        # Check if expired
        expires_at = Time.parse(cached_data["expires_at"])
        return false if expires_at < Time.current

        # Validate the actual response data
        response_data = cached_data["data"]
        required_fields = %w[message confidence_score credits_used provider]

        required_fields.all? { |field| response_data.key?(field) }
    rescue => e
        Rails.logger.error("Error validating cached response: #{e.message}")
        false
      end

        def cacheable_response?(response_data)
        return false unless response_data.is_a?(Hash)
        return false unless response_data["message"]
        return false unless response_data["confidence_score"]
        return false unless response_data["provider"]

        # Don't cache responses with low confidence
        confidence = response_data["confidence_score"].to_f
        return false if confidence < 0.7

        # Don't cache very large responses
        serialized_size = response_data.to_json.bytesize
        return false if serialized_size > MAX_CACHE_SIZE

        true
      end

        def increment_cache_stats(stat_type)
        stats_key = "ai_cache_stats"
        current_stats = @cache.read(stats_key) || {}
        current_stats[stat_type] = (current_stats[stat_type] || 0) + 1
          @cache.write(stats_key, current_stats, expires_in: 1.day)
      end

        def get_cache_stats
          @cache.read("ai_cache_stats") || {}
      end

        def reset_cache_stats
          @cache.write("ai_cache_stats", {}, expires_in: 1.day)
      end

        def calculate_hit_rate(stats)
        total = (stats[:hits] || 0) + (stats[:misses] || 0)
        return 0.0 if total == 0

        ((stats[:hits] || 0).to_f / total * 100).round(2)
      end

        def count_total_keys
        pattern = "ai_response:*"
          @cache.redis&.keys(pattern)&.count || 0
      rescue
        0
      end
    end
  end
end
