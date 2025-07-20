# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      # Basic stats for overview
      @total_users = User.count
      @total_files = ExcelFile.count
      @total_analyses = Analysis.count
      @recent_users = User.recent.limit(5)
      @recent_files = ExcelFile.recent.limit(5)
      @recent_analyses = Analysis.recent.limit(5)

      # Load system stats
      system_stats_result = AdminDashboard::Handlers::SystemStatsHandler.new(
        user: current_user,
        time_range: params[:time_range] || "today"
      ).execute

      if system_stats_result.success?
        @system_stats = system_stats_result.value
      else
        @system_stats = {}
        flash.now[:alert] = "Failed to load system statistics"
      end
    end

    def analytics
      # Load advanced analytics
      analytics_result = AdminDashboard::Handlers::AdvancedAnalyticsHandler.new(
        user: current_user,
        metric_type: params[:metric_type] || "all",
        timeframe: params[:timeframe] || "24h"
      ).execute

      respond_to do |format|
        format.html do
          if analytics_result.success?
            @analytics = analytics_result.value
            @timeframe = params[:timeframe] || "24h"
            @metric_type = params[:metric_type] || "all"
          else
            @analytics = {}
            flash.now[:alert] = "Failed to load analytics data"
          end
        end

        format.json do
          if analytics_result.success?
            render json: {
              status: "success",
              data: analytics_result.value,
              timestamp: Time.current.iso8601
            }
          else
            render json: {
              status: "error",
              message: analytics_result.error.message,
              timestamp: Time.current.iso8601
            }, status: :internal_server_error
          end
        end
      end
    end

    def real_time_metrics
      # Get real-time system metrics for AJAX updates
      system_stats_result = AdminDashboard::Handlers::SystemStatsHandler.new(
        user: current_user,
        time_range: "today"
      ).execute

      if system_stats_result.success?
        render json: {
          status: "success",
          metrics: {
            active_users: system_stats_result.value[:recent_activity][:new_users],
            processing_files: ExcelFile.where(status: :processing).count,
            queue_status: get_queue_metrics,
            system_health: system_stats_result.value[:system_health],
            performance: get_performance_metrics
          },
          timestamp: Time.current.iso8601
        }
      else
        render json: {
          status: "error",
          message: "Failed to fetch real-time metrics",
          timestamp: Time.current.iso8601
        }, status: :internal_server_error
      end
    end

    def export_analytics
      analytics_result = AdminDashboard::Handlers::AdvancedAnalyticsHandler.new(
        user: current_user,
        metric_type: params[:metric_type] || "all",
        timeframe: params[:timeframe] || "24h"
      ).execute

      if analytics_result.success?
        filename = "analytics_#{params[:timeframe]}_#{Date.current.strftime('%Y%m%d')}.json"

        respond_to do |format|
          format.json do
            send_data analytics_result.value.to_json,
                      filename: filename,
                      type: "application/json",
                      disposition: "attachment"
          end

          format.csv do
            csv_data = generate_csv_from_analytics(analytics_result.value)
            send_data csv_data,
                      filename: filename.gsub(".json", ".csv"),
                      type: "text/csv",
                      disposition: "attachment"
          end
        end
      else
        redirect_to admin_dashboard_analytics_path,
                   alert: "Failed to export analytics: #{analytics_result.error.message}"
      end
    end

    private

    def get_queue_metrics
      {
        total_jobs: SolidQueue::Job.count,
        pending_jobs: SolidQueue::Job.where(finished_at: nil).count,
        failed_jobs: SolidQueue::Job.where.not(failed_at: nil).count,
        processing_jobs: SolidQueue::Job.where(finished_at: nil, failed_at: nil).count,
        avg_wait_time: calculate_avg_wait_time
      }
    end

    def get_performance_metrics
      {
        memory_usage: get_memory_usage_percentage,
        active_connections: ActiveRecord::Base.connection_pool.stat[:busy],
        response_time: get_avg_response_time,
        error_rate: calculate_error_rate
      }
    end

    def calculate_avg_wait_time
      pending_jobs = SolidQueue::Job.where(finished_at: nil).order(:created_at)
      return 0 if pending_jobs.empty?

      total_wait_time = pending_jobs.sum { |job| Time.current - job.created_at }
      (total_wait_time / pending_jobs.count).round(2)
    end

    def get_memory_usage_percentage
      begin
        rss_kb = `ps -o rss= -p #{Process.pid}`.to_i
        # Assuming 2GB total memory allocation
        (rss_kb.to_f / (2 * 1024 * 1024) * 100).round(2)
      rescue StandardError
        0.0
      end
    end

    def get_avg_response_time
      # This would typically come from APM tools like Scout or New Relic
      # For now, return a calculated estimate based on recent activity
      recent_analyses = Analysis.where(created_at: 1.hour.ago..Time.current)
      return 0 if recent_analyses.empty?

      # Estimate based on file sizes and complexity
      avg_file_size = recent_analyses.joins(:excel_file).average("excel_files.file_size") || 0
      base_time = 100 # Base response time in milliseconds
      size_factor = (avg_file_size / 1.megabyte) * 50 # Additional time per MB

      (base_time + size_factor).round(2)
    end

    def calculate_error_rate
      last_hour = 1.hour.ago..Time.current
      total_analyses = Analysis.where(created_at: last_hour).count
      failed_files = ExcelFile.where(status: :failed, updated_at: last_hour).count

      return 0.0 if total_analyses == 0
      (failed_files.to_f / total_analyses * 100).round(2)
    end

    def generate_csv_from_analytics(analytics_data)
      require "csv"

      CSV.generate(headers: true) do |csv|
        # Headers
        csv << [ "Metric", "Value", "Timestamp" ]

        # Flatten the analytics data for CSV export
        flatten_analytics_for_csv(analytics_data, csv)

        csv << [ "Export Generated", Time.current.iso8601, Time.current.iso8601 ]
      end
    end

    def flatten_analytics_for_csv(data, csv, prefix = "")
      data.each do |key, value|
        current_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"

        if value.is_a?(Hash)
          flatten_analytics_for_csv(value, csv, current_key)
        elsif value.is_a?(Array)
          value.each_with_index do |item, index|
            if item.is_a?(Hash)
              flatten_analytics_for_csv(item, csv, "#{current_key}[#{index}]")
            else
              csv << [ "#{current_key}[#{index}]", item.to_s, Time.current.iso8601 ]
            end
          end
        else
          csv << [ current_key, value.to_s, Time.current.iso8601 ]
        end
      end
    end
  end
end
