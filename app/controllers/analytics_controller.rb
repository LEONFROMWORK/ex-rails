# frozen_string_literal: true

class AnalyticsController < ApplicationController
  before_action :authenticate_user!

  def index
    @analytics_data = calculate_analytics_data
  end

  private

  def calculate_analytics_data
    return {} unless current_user

    # Safe access with error handling
    begin
      {
        total_files: safe_count { current_user.excel_files.count },
        total_analyses: safe_count { current_user.analyses.count },
        total_credits_used: safe_sum { current_user.analyses.sum(:credits_used) } || 0,
        files_this_week: safe_count { current_user.excel_files.where(created_at: 1.week.ago..Time.current).count },
        analyses_this_week: safe_count { current_user.analyses.where(created_at: 1.week.ago..Time.current).count },
        files_by_status: safe_group { current_user.excel_files.group(:status).count },
        analyses_by_tier: safe_group { current_user.analyses.group(:ai_tier_used).count },
        recent_files: safe_query { current_user.excel_files.order(created_at: :desc).limit(5) },
        monthly_usage: monthly_usage_data
      }
    rescue => e
      Rails.logger.error "Analytics calculation error: #{e.message}"
      default_analytics_data
    end
  end

  def monthly_usage_data
    begin
      # Return empty hash if analyses association doesn't exist
      return {} unless current_user.respond_to?(:analyses)

      # Group analyses by month using standard Rails methods
      analyses = current_user.analyses
                            .where(created_at: 6.months.ago..Time.current)
                            .pluck(:created_at)

      # Group by year-month and count
      monthly_counts = analyses.group_by { |date| date.beginning_of_month }.transform_values(&:count)

      # Fill in missing months with 0
      6.downto(0).each_with_object({}) do |months_ago, result|
        month = months_ago.months.ago.beginning_of_month
        result[month.strftime("%Y-%m")] = monthly_counts[month] || 0
      end
    rescue => e
      Rails.logger.warn "Monthly usage data error: #{e.message}"
      {}
    end
  end

  def safe_count
    yield
  rescue => e
    Rails.logger.warn "Safe count error: #{e.message}"
    0
  end

  def safe_sum
    yield
  rescue => e
    Rails.logger.warn "Safe sum error: #{e.message}"
    0
  end

  def safe_group
    yield
  rescue => e
    Rails.logger.warn "Safe group error: #{e.message}"
    {}
  end

  def safe_query
    yield
  rescue => e
    Rails.logger.warn "Safe query error: #{e.message}"
    []
  end

  def default_analytics_data
    {
      total_files: 0,
      total_analyses: 0,
      total_credits_used: 0,
      files_this_week: 0,
      analyses_this_week: 0,
      files_by_status: {},
      analyses_by_tier: {},
      recent_files: [],
      monthly_usage: {}
    }
  end

  def authenticate_user!
    redirect_to login_path unless user_signed_in?
  end
end
