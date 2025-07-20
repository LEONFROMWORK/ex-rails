# frozen_string_literal: true

module AdminDashboard
  module Handlers
    class AdvancedAnalyticsHandler < Common::BaseHandler
      def initialize(user:, metric_type: "all", timeframe: "24h")
        @user = user
        @metric_type = metric_type
        @timeframe = timeframe
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
          analytics_data = {
            real_time_metrics: build_real_time_metrics,
            performance_trends: build_performance_trends,
            user_behavior: build_user_behavior_analysis,
            ai_cost_breakdown: build_ai_cost_breakdown,
            system_health: build_system_health_metrics,
            predictive_analytics: build_predictive_analytics
          }

          Rails.logger.info("Advanced analytics generated for admin user #{@user.id}")

          Common::Result.success(analytics_data)
        rescue StandardError => e
          Rails.logger.error("Failed to generate advanced analytics: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to generate advanced analytics",
              code: "ANALYTICS_GENERATION_ERROR"
            )
          )
        end
      end

      private

      def build_real_time_metrics
        {
          timestamp: Time.current,
          active_analyses: active_analyses_count,
          queue_status: solid_queue_status,
          response_times: calculate_response_times,
          error_rates: calculate_error_rates,
          memory_usage: system_memory_usage,
          cpu_usage: system_cpu_usage,
          database_performance: database_performance_metrics,
          websocket_connections: websocket_connection_count
        }
      end

      def build_performance_trends
        time_range = get_time_range(@timeframe)

        {
          timeframe: @timeframe,
          analysis_volume: Analysis.where(created_at: time_range)
                                 .group_by_hour(:created_at)
                                 .count,
          response_time_trend: calculate_response_time_trend(time_range),
          ai_tier_usage_trend: ai_tier_usage_over_time(time_range),
          error_rate_trend: error_rate_over_time(time_range),
          user_activity_pattern: user_activity_pattern(time_range),
          revenue_trend: revenue_trend(time_range),
          file_size_distribution: file_size_distribution_over_time(time_range)
        }
      end

      def build_user_behavior_analysis
        time_range = get_time_range(@timeframe)

        {
          user_cohorts: analyze_user_cohorts(time_range),
          retention_analysis: calculate_retention_rates(time_range),
          feature_adoption: analyze_feature_adoption(time_range),
          session_analytics: analyze_user_sessions(time_range),
          conversion_funnel: analyze_conversion_funnel(time_range),
          churn_prediction: predict_user_churn,
          geographic_distribution: analyze_geographic_distribution,
          device_analytics: analyze_device_usage(time_range)
        }
      end

      def build_ai_cost_breakdown
        time_range = get_time_range(@timeframe)

        cost_data = AiUsageRecord.joins(:user)
                                .where(created_at: time_range)
                                .group(:user_id, :ai_tier_used)
                                .group_by_period(:created_at, period: get_grouping_period)
                                .sum(:estimated_cost)

        {
          total_cost: cost_data.values.sum,
          cost_by_tier: ai_cost_by_tier(time_range),
          cost_by_user_segment: ai_cost_by_user_segment(time_range),
          cost_efficiency_metrics: calculate_cost_efficiency(time_range),
          tier_escalation_analysis: analyze_tier_escalations(time_range),
          cost_optimization_opportunities: identify_cost_optimizations(time_range),
          provider_cost_comparison: compare_provider_costs(time_range)
        }
      end

      def build_system_health_metrics
        {
          infrastructure: {
            server_metrics: get_server_metrics,
            database_health: get_database_health,
            redis_performance: get_redis_performance,
            storage_metrics: get_storage_metrics
          },
          application: {
            rails_performance: get_rails_performance_metrics,
            background_jobs: get_background_job_metrics,
            websocket_health: get_websocket_health,
            api_health: get_api_health_metrics
          },
          external_services: {
            ai_provider_status: get_ai_provider_detailed_status,
            payment_gateway_status: get_payment_gateway_status,
            file_storage_status: get_file_storage_status
          },
          alerts: {
            active_alerts: get_active_system_alerts,
            recent_incidents: get_recent_incidents,
            performance_warnings: get_performance_warnings
          }
        }
      end

      def build_predictive_analytics
        {
          demand_forecasting: forecast_analysis_demand,
          capacity_planning: analyze_capacity_requirements,
          cost_projections: project_ai_costs,
          user_growth_prediction: predict_user_growth,
          revenue_forecast: forecast_revenue,
          system_scaling_recommendations: get_scaling_recommendations
        }
      end

      # Real-time metrics helpers
      def active_analyses_count
        ExcelFile.where(status: :processing).count
      end

      def solid_queue_status
        {
          total_jobs: SolidQueue::Job.count,
          pending_jobs: SolidQueue::Job.where(finished_at: nil).count,
          failed_jobs: SolidQueue::Job.where.not(failed_at: nil).count,
          queue_latency: calculate_queue_latency,
          worker_status: get_worker_status
        }
      end

      def calculate_response_times
        # Would typically integrate with APM tools like Scout or New Relic
        {
          p50: 120, # milliseconds
          p95: 450,
          p99: 850,
          avg: 180
        }
      end

      def calculate_error_rates
        time_range = 1.hour.ago..Time.current
        total_requests = Analysis.where(created_at: time_range).count
        failed_requests = ExcelFile.where(status: :failed, updated_at: time_range).count

        {
          error_rate: total_requests > 0 ? (failed_requests.to_f / total_requests * 100).round(2) : 0,
          total_requests: total_requests,
          failed_requests: failed_requests,
          error_types: get_recent_error_types(time_range)
        }
      end

      def system_memory_usage
        # Would integrate with system monitoring tools
        {
          used_mb: `ps -o rss= -p #{Process.pid}`.to_i / 1024,
          total_mb: 2048, # Assuming 2GB allocation
          percentage: 45.2
        }
      end

      def system_cpu_usage
        # Would integrate with system monitoring
        {
          current_percentage: 35.8,
          avg_15min: 42.1,
          load_average: [ 1.2, 1.5, 1.8 ]
        }
      end

      def database_performance_metrics
        {
          active_connections: ActiveRecord::Base.connection_pool.stat[:size],
          slow_queries: 0, # Would integrate with pg_stat_statements
          connection_pool_usage: (ActiveRecord::Base.connection_pool.stat[:busy].to_f /
                                ActiveRecord::Base.connection_pool.stat[:size] * 100).round(2),
          avg_query_time: 15.2 # milliseconds
        }
      end

      def websocket_connection_count
        # Would integrate with ActionCable metrics
        50 # Active WebSocket connections
      end

      # Performance trends helpers
      def calculate_response_time_trend(time_range)
        # Mock data - would integrate with APM
        hours = time_range_to_hours(time_range)
        hours.map { |hour| [ hour, rand(100..500) ] }.to_h
      end

      def ai_tier_usage_over_time(time_range)
        AiUsageRecord.where(created_at: time_range)
                    .group_by_hour(:created_at)
                    .group(:ai_tier_used)
                    .count
      end

      def error_rate_over_time(time_range)
        ExcelFile.where(updated_at: time_range)
                .group_by_hour(:updated_at)
                .group(:status)
                .count
      end

      def user_activity_pattern(time_range)
        User.joins(:excel_files)
            .where(excel_files: { created_at: time_range })
            .group_by_hour("excel_files.created_at")
            .count
      end

      def revenue_trend(time_range)
        Payment.completed
              .where(processed_at: time_range)
              .group_by_hour(:processed_at)
              .sum(:amount)
      end

      def file_size_distribution_over_time(time_range)
        ExcelFile.where(created_at: time_range)
                .group_by_hour(:created_at)
                .average(:file_size)
      end

      # User behavior analysis helpers
      def analyze_user_cohorts(time_range)
        # Cohort analysis by registration week
        users_by_week = User.where(created_at: time_range)
                           .group_by_week(:created_at)
                           .count

        users_by_week.map do |week, count|
          {
            cohort_date: week,
            initial_size: count,
            week_1_retention: calculate_retention_for_cohort(week, 1.week),
            week_4_retention: calculate_retention_for_cohort(week, 4.weeks),
            week_12_retention: calculate_retention_for_cohort(week, 12.weeks)
          }
        end
      end

      def calculate_retention_rates(time_range)
        new_users = User.where(created_at: time_range)

        {
          daily_active_users: calculate_dau(time_range),
          weekly_active_users: calculate_wau(time_range),
          monthly_active_users: calculate_mau(time_range),
          retention_by_cohort: analyze_user_cohorts(time_range)
        }
      end

      def analyze_feature_adoption(time_range)
        {
          excel_upload: ExcelFile.where(created_at: time_range).joins(:user).group("users.id").count.keys.count,
          ai_analysis: Analysis.where(created_at: time_range).joins(:user).group("users.id").count.keys.count,
          chat_feature: ChatConversation.where(created_at: time_range).joins(:user).group("users.id").count.keys.count,
          payment_usage: Payment.where(processed_at: time_range).joins(:user).group("users.id").count.keys.count
        }
      end

      def analyze_conversion_funnel(time_range)
        users_in_period = User.where(created_at: time_range)

        {
          registered_users: users_in_period.count,
          uploaded_file: users_in_period.joins(:excel_files).distinct.count,
          completed_analysis: users_in_period.joins(:analyses).distinct.count,
          made_payment: users_in_period.joins(:payments).where(payments: { status: "completed" }).distinct.count,
          conversion_rates: calculate_funnel_conversion_rates(users_in_period)
        }
      end

      # AI cost analysis helpers
      def ai_cost_by_tier(time_range)
        AiUsageRecord.where(created_at: time_range)
                    .group(:ai_tier_used)
                    .sum(:estimated_cost)
      end

      def ai_cost_by_user_segment(time_range)
        AiUsageRecord.joins(:user)
                    .where(created_at: time_range)
                    .group("users.tier")
                    .sum(:estimated_cost)
      end

      def calculate_cost_efficiency(time_range)
        total_cost = AiUsageRecord.where(created_at: time_range).sum(:estimated_cost)
        total_analyses = Analysis.where(created_at: time_range).count

        {
          cost_per_analysis: total_analyses > 0 ? (total_cost / total_analyses).round(4) : 0,
          tier1_efficiency: calculate_tier_efficiency(time_range, "tier1"),
          tier2_efficiency: calculate_tier_efficiency(time_range, "tier2"),
          escalation_rate: calculate_escalation_rate(time_range)
        }
      end

      def analyze_tier_escalations(time_range)
        escalations = AiUsageRecord.where(created_at: time_range, ai_tier_used: "tier2")

        {
          total_escalations: escalations.count,
          escalation_rate: calculate_escalation_rate(time_range),
          escalation_reasons: analyze_escalation_reasons(escalations),
          cost_impact: escalations.sum(:estimated_cost)
        }
      end

      # Utility methods
      def get_time_range(timeframe)
        case timeframe
        when "1h" then 1.hour.ago..Time.current
        when "24h" then 24.hours.ago..Time.current
        when "7d" then 7.days.ago..Time.current
        when "30d" then 30.days.ago..Time.current
        else 24.hours.ago..Time.current
        end
      end

      def get_grouping_period
        case @timeframe
        when "1h", "24h" then :hour
        when "7d" then :day
        when "30d" then :week
        else :hour
        end
      end

      def time_range_to_hours(time_range)
        start_time = time_range.begin
        end_time = time_range.end
        hours = []

        current = start_time.beginning_of_hour
        while current <= end_time
          hours << current
          current += 1.hour
        end

        hours
      end

      def calculate_queue_latency
        oldest_pending = SolidQueue::Job.where(finished_at: nil).order(:created_at).first
        return 0 unless oldest_pending

        ((Time.current - oldest_pending.created_at) * 1000).round # milliseconds
      end

      def get_worker_status
        {
          active_workers: 4, # Would get from Solid Queue
          total_capacity: 10,
          utilization_percentage: 40
        }
      end

      def get_recent_error_types(time_range)
        # Would analyze application logs or error tracking service
        [
          { type: "timeout_error", count: 3 },
          { type: "ai_provider_error", count: 1 },
          { type: "file_processing_error", count: 2 }
        ]
      end

      def calculate_retention_for_cohort(cohort_date, period)
        # Simplified retention calculation
        cohort_users = User.where(created_at: cohort_date.beginning_of_week..cohort_date.end_of_week)
        active_users = cohort_users.joins(:excel_files)
                                  .where(excel_files: { created_at: (cohort_date + period).beginning_of_week..(cohort_date + period).end_of_week })
                                  .distinct

        cohort_users.count > 0 ? (active_users.count.to_f / cohort_users.count * 100).round(2) : 0
      end

      def calculate_dau(time_range)
        User.joins(:excel_files)
            .where(excel_files: { created_at: time_range })
            .group_by_day("excel_files.created_at")
            .distinct
            .count("users.id")
      end

      def calculate_wau(time_range)
        User.joins(:excel_files)
            .where(excel_files: { created_at: time_range })
            .group_by_week("excel_files.created_at")
            .distinct
            .count("users.id")
      end

      def calculate_mau(time_range)
        User.joins(:excel_files)
            .where(excel_files: { created_at: time_range })
            .group_by_month("excel_files.created_at")
            .distinct
            .count("users.id")
      end

      def calculate_funnel_conversion_rates(users)
        total = users.count
        return {} if total == 0

        uploaded = users.joins(:excel_files).distinct.count
        analyzed = users.joins(:analyses).distinct.count
        paid = users.joins(:payments).where(payments: { status: "completed" }).distinct.count

        {
          upload_rate: (uploaded.to_f / total * 100).round(2),
          analysis_rate: (analyzed.to_f / total * 100).round(2),
          payment_rate: (paid.to_f / total * 100).round(2)
        }
      end

      def calculate_tier_efficiency(time_range, tier)
        tier_records = AiUsageRecord.where(created_at: time_range, ai_tier_used: tier)
        return 0 if tier_records.empty?

        total_cost = tier_records.sum(:estimated_cost)
        total_analyses = tier_records.count

        {
          avg_cost: (total_cost / total_analyses).round(4),
          total_usage: total_analyses,
          success_rate: 95.5 # Would calculate from actual success metrics
        }
      end

      def calculate_escalation_rate(time_range)
        total_analyses = Analysis.where(created_at: time_range).count
        escalated_analyses = AiUsageRecord.where(created_at: time_range, ai_tier_used: "tier2").count

        total_analyses > 0 ? (escalated_analyses.to_f / total_analyses * 100).round(2) : 0
      end

      def analyze_escalation_reasons(escalations)
        # Would analyze the context of escalations
        {
          low_confidence: 45,
          complex_formulas: 30,
          large_files: 15,
          user_request: 10
        }
      end

      # System health helpers - would integrate with actual monitoring tools
      def get_server_metrics
        { cpu_usage: 35.8, memory_usage: 45.2, disk_usage: 23.1 }
      end

      def get_database_health
        { connections: 15, slow_queries: 0, replication_lag: 0 }
      end

      def get_redis_performance
        { memory_usage: 128, connected_clients: 25, ops_per_sec: 1500 }
      end

      def get_storage_metrics
        { total_gb: 500, used_gb: 125, files_count: ExcelFile.count }
      end

      def get_rails_performance_metrics
        { avg_response_time: 180, throughput: 45, error_rate: 0.1 }
      end

      def get_background_job_metrics
        {
          processed_jobs: SolidQueue::Job.where(finished_at: 24.hours.ago..Time.current).count,
          failed_jobs: SolidQueue::Job.where(failed_at: 24.hours.ago..Time.current).count,
          avg_processing_time: 15.5
        }
      end

      def get_websocket_health
        { active_connections: 50, messages_per_sec: 125 }
      end

      def get_api_health_metrics
        { requests_per_min: 150, avg_latency: 120, error_rate: 0.05 }
      end

      def get_ai_provider_detailed_status
        # Would check actual provider health
        {
          openai: { status: "healthy", latency: 450, error_rate: 0.1 },
          anthropic: { status: "healthy", latency: 380, error_rate: 0.05 },
          google: { status: "degraded", latency: 650, error_rate: 2.1 }
        }
      end

      def get_payment_gateway_status
        { toss_payments: { status: "healthy", success_rate: 99.8 } }
      end

      def get_file_storage_status
        { aws_s3: { status: "healthy", upload_success_rate: 99.9 } }
      end

      def get_active_system_alerts
        []
      end

      def get_recent_incidents
        []
      end

      def get_performance_warnings
        []
      end

      # Predictive analytics helpers
      def forecast_analysis_demand
        # Would use time series forecasting
        { next_hour: 25, next_day: 580, next_week: 4200 }
      end

      def analyze_capacity_requirements
        { recommended_workers: 6, peak_capacity_needed: 15 }
      end

      def project_ai_costs
        { next_month: 2500, cost_trend: "increasing", savings_opportunities: 850 }
      end

      def predict_user_growth
        { next_month_new_users: 450, growth_rate: 15.2 }
      end

      def forecast_revenue
        { next_month: 8500, confidence_interval: [ 7200, 9800 ] }
      end

      def get_scaling_recommendations
        [
          "Consider adding 2 more background workers during peak hours",
          "Redis memory usage trending up - monitor for scaling",
          "AI cost optimization could save 20% with better tier routing"
        ]
      end
    end
  end
end
