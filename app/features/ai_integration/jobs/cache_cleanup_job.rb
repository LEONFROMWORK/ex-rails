# frozen_string_literal: true

module AiIntegration
  module Jobs
    class CacheCleanupJob < ApplicationJob
      queue_as :default

      def perform
        cache_service = AiIntegration::Services::AiResponseCache.new

        Rails.logger.info("Starting AI cache cleanup job")

        # Clear expired entries
        expired_count = cache_service.clear_expired

        # Log cache statistics
        stats = cache_service.stats
        Rails.logger.info("AI cache cleanup completed: #{expired_count} expired entries removed")
        Rails.logger.info("AI cache stats: #{stats}")

        # Alert if cache hit rate is low
        if stats[:hit_rate] < 30 && stats[:hits] + stats[:misses] > 100
          Rails.logger.warn("AI cache hit rate is low (#{stats[:hit_rate]}%), consider optimizing cache strategy")
        end

        expired_count
      rescue => e
        Rails.logger.error("AI cache cleanup job failed: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        raise
      end
    end
  end
end
