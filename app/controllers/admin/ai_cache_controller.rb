# frozen_string_literal: true

module Admin
  class AiCacheController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin_access

    def index
      @cache_service = Ai::ResponseCache.new
      @stats = @cache_service.stats
      @cache_stats_history = get_cache_stats_history
    end

    def show
      @cache_service = Ai::ResponseCache.new
      @stats = @cache_service.stats

      respond_to do |format|
        format.html { redirect_to admin_ai_cache_index_path }
        format.json { render json: @stats }
      end
    end

    def clear_expired
      @cache_service = Ai::ResponseCache.new
      expired_count = @cache_service.clear_expired

      flash[:notice] = "Cleared #{expired_count} expired cache entries"
      redirect_to admin_ai_cache_index_path
    end

    def clear_all
      return unless params[:confirm] == "yes"

      @cache_service = Ai::ResponseCache.new
      deleted_count = @cache_service.clear_all

      flash[:notice] = "Cleared all #{deleted_count} cache entries"
      redirect_to admin_ai_cache_index_path
    end

    private

    def ensure_admin_access
      redirect_to root_path unless current_user.can_access_admin?
    end

    def get_cache_stats_history
      # This would typically come from a time-series database
      # For now, return mock data for demonstration
      [
        { date: 1.day.ago.to_date, hit_rate: 75.2, hits: 1250, misses: 412 },
        { date: 2.days.ago.to_date, hit_rate: 72.8, hits: 1188, misses: 443 },
        { date: 3.days.ago.to_date, hit_rate: 78.1, hits: 1356, misses: 381 },
        { date: 4.days.ago.to_date, hit_rate: 71.3, hits: 1098, misses: 442 },
        { date: 5.days.ago.to_date, hit_rate: 74.6, hits: 1203, misses: 410 },
        { date: 6.days.ago.to_date, hit_rate: 76.9, hits: 1289, misses: 387 },
        { date: 7.days.ago.to_date, hit_rate: 73.4, hits: 1167, misses: 423 }
      ]
    end
  end
end
