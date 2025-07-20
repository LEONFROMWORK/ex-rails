# frozen_string_literal: true

module AdminDashboard
  module Handlers
    class SystemStatsHandler < Common::BaseHandler
      def initialize(user:, time_range: "today")
        @user = user
        @time_range = time_range
      end

      def execute
        # Check admin access
        unless @user.can_access_admin?
          return Common::Result.failure(
            Common::Errors::AuthorizationError.new(
              message: "Admin access required"
            )
          )
        end

        begin
          stats = calculate_system_stats

          Rails.logger.info("System stats generated for admin user #{@user.id}")

          Common::Result.success(stats)
        rescue StandardError => e
          Rails.logger.error("Failed to generate system stats: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to generate system statistics",
              code: "STATS_GENERATION_ERROR"
            )
          )
        end
      end

      private

      def calculate_system_stats
        time_filter = get_time_filter

        {
          overview: {
            total_users: User.count,
            active_users: User.active.count,
            total_files: ExcelFile.count,
            total_analyses: Analysis.count,
            total_revenue: Payment.completed.sum(:amount)
          },
          recent_activity: {
            new_users: User.where(created_at: time_filter).count,
            files_uploaded: ExcelFile.where(created_at: time_filter).count,
            analyses_completed: Analysis.where(created_at: time_filter).count,
            revenue_generated: Payment.completed.where(processed_at: time_filter).sum(:amount)
          },
          system_health: {
            ai_providers: get_ai_provider_status,
            storage_usage: calculate_storage_usage,
            error_rate: calculate_error_rate(time_filter)
          },
          user_distribution: {
            by_tier: User.group(:tier).count,
            by_role: User.group(:role).count,
            credits_distribution: calculate_credits_distribution
          },
          performance_metrics: {
            avg_analysis_time: calculate_avg_analysis_time(time_filter),
            success_rate: calculate_success_rate(time_filter),
            top_error_types: get_top_error_types(time_filter)
          }
        }
      end

      def get_time_filter
        case @time_range
        when "today"
          Time.current.beginning_of_day..Time.current.end_of_day
        when "week"
          1.week.ago..Time.current
        when "month"
          1.month.ago..Time.current
        else
          Time.current.beginning_of_day..Time.current.end_of_day
        end
      end

      def get_ai_provider_status
        providers = [ "openai", "anthropic", "google" ]

        providers.map do |provider|
          begin
            provider_instance = "Infrastructure::AiProviders::#{provider.camelize}Provider".constantize.new
            status = provider_instance.health_check

            {
              name: provider,
              status: status[:status],
              details: status
            }
          rescue StandardError => e
            {
              name: provider,
              status: "error",
              error: e.message
            }
          end
        end
      end

      def calculate_storage_usage
        {
          total_files: ExcelFile.count,
          total_size_mb: ExcelFile.sum(:file_size) / 1.megabyte,
          avg_file_size_mb: ExcelFile.average(:file_size).to_f / 1.megabyte
        }
      end

      def calculate_error_rate(time_filter)
        total_analyses = Analysis.where(created_at: time_filter).count
        return 0 if total_analyses == 0

        # Consider analyses with high error counts as "failed"
        failed_analyses = Analysis.where(created_at: time_filter)
                                .joins(:excel_file)
                                .where(excel_files: { status: "failed" })
                                .count

        (failed_analyses.to_f / total_analyses * 100).round(2)
      end

      def calculate_credits_distribution
        {
          total_credits: User.sum(:credits),
          avg_credits_per_user: User.average(:credits).to_f.round(2),
          users_with_credits: User.where("credits > 0").count,
          users_without_credits: User.where(credits: 0).count
        }
      end

      def calculate_avg_analysis_time(time_filter)
        # This would need to be implemented based on actual timing data
        # For now, return a mock value
        {
          tier1: "15s",
          tier2: "30s",
          overall: "20s"
        }
      end

      def calculate_success_rate(time_filter)
        total_analyses = Analysis.where(created_at: time_filter).count
        return 100.0 if total_analyses == 0

        # Consider analyses with AI results as successful
        successful_analyses = Analysis.where(created_at: time_filter)
                                    .where.not(ai_analysis: nil)
                                    .count

        (successful_analyses.to_f / total_analyses * 100).round(2)
      end

      def get_top_error_types(time_filter)
        # This would analyze the detected_errors JSON column
        # For now, return mock data
        [
          { type: "formula_error", count: 45 },
          { type: "data_validation", count: 32 },
          { type: "circular_reference", count: 18 },
          { type: "format_inconsistency", count: 12 }
        ]
      end
    end
  end
end
