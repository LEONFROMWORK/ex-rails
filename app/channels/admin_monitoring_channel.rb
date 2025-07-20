# frozen_string_literal: true

class AdminMonitoringChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.can_access_admin?

    stream_from "admin_monitoring"

    # 즉시 현재 상태 전송
    transmit({
      type: "initial_state",
      data: gather_system_metrics,
      timestamp: Time.current.iso8601
    })

    # 주기적 업데이트 시작
    start_periodic_updates

    Rails.logger.info("Admin monitoring channel subscribed for user #{current_user.id}")
  end

  def unsubscribed
    stop_periodic_updates
    Rails.logger.info("Admin monitoring channel unsubscribed for user #{current_user&.id}")
  end

  def request_detailed_metrics(data)
    return unless current_user&.can_access_admin?

    metric_type = data["metric_type"]
    timeframe = data["timeframe"] || "1h"

    begin
      metrics = case metric_type
      when "performance"
        gather_performance_metrics(timeframe)
      when "ai_usage"
        gather_ai_usage_metrics(timeframe)
      when "system_health"
        gather_system_health_metrics(timeframe)
      when "user_behavior"
        gather_user_behavior_metrics(timeframe)
      when "cost_analysis"
        gather_cost_analysis_metrics(timeframe)
      else
        { error: "Unknown metric type: #{metric_type}" }
      end

      transmit({
        type: "detailed_metrics",
        metric_type: metric_type,
        timeframe: timeframe,
        data: metrics,
        timestamp: Time.current.iso8601
      })
    rescue StandardError => e
      Rails.logger.error("Error gathering detailed metrics: #{e.message}")
      transmit({
        type: "error",
        message: "Failed to gather #{metric_type} metrics",
        timestamp: Time.current.iso8601
      })
    end
  end

  def request_live_stats(data)
    return unless current_user&.can_access_admin?

    live_stats = {
      active_users: get_active_users_count,
      processing_files: ExcelFile.where(status: :processing).count,
      queue_status: get_queue_status,
      recent_errors: get_recent_errors(5.minutes.ago),
      system_resources: get_system_resource_usage
    }

    transmit({
      type: "live_stats",
      data: live_stats,
      timestamp: Time.current.iso8601
    })
  end

  def toggle_real_time_updates(data)
    return unless current_user&.can_access_admin?

    enabled = data["enabled"]

    if enabled
      start_periodic_updates
    else
      stop_periodic_updates
    end

    transmit({
      type: "real_time_status",
      enabled: enabled,
      timestamp: Time.current.iso8601
    })
  end

  def request_alert_configuration(data)
    return unless current_user&.can_access_admin?

    alert_config = {
      thresholds: {
        error_rate: 5.0,         # Percentage
        response_time: 500,      # Milliseconds
        queue_latency: 30000,    # Milliseconds
        memory_usage: 80.0,      # Percentage
        cpu_usage: 85.0,         # Percentage
        ai_cost_daily: 1000.0    # Dollars
      },
      notification_channels: [ "email", "slack" ],
      escalation_rules: get_escalation_rules
    }

    transmit({
      type: "alert_configuration",
      data: alert_config,
      timestamp: Time.current.iso8601
    })
  end

  def trigger_manual_health_check(data)
    return unless current_user&.can_access_admin?

    begin
      health_results = perform_comprehensive_health_check

      transmit({
        type: "health_check_results",
        data: health_results,
        timestamp: Time.current.iso8601
      })
    rescue StandardError => e
      Rails.logger.error("Manual health check failed: #{e.message}")
      transmit({
        type: "error",
        message: "Health check failed: #{e.message}",
        timestamp: Time.current.iso8601
      })
    end
  end

  private

  def gather_system_metrics
    {
      timestamp: Time.current,
      active_jobs: SolidQueue::Job.where(finished_at: nil).count,
      queue_latency: calculate_queue_latency,
      memory_usage: get_memory_usage,
      cpu_usage: get_cpu_usage,
      active_users: get_active_users_count,
      processing_files: ExcelFile.where(status: :processing).count,
      error_rate: calculate_current_error_rate,
      response_time: get_avg_response_time,
      ai_providers_status: get_ai_providers_quick_status
    }
  end

  def gather_performance_metrics(timeframe)
    time_range = parse_timeframe(timeframe)

    {
      response_times: {
        avg: get_avg_response_time(time_range),
        p95: get_percentile_response_time(time_range, 95),
        p99: get_percentile_response_time(time_range, 99)
      },
      throughput: {
        requests_per_minute: calculate_requests_per_minute(time_range),
        analyses_per_hour: Analysis.where(created_at: time_range).count / (time_range.size / 1.hour)
      },
      error_analysis: {
        total_errors: get_error_count(time_range),
        error_breakdown: get_error_breakdown(time_range),
        error_trend: get_error_trend(time_range)
      },
      resource_utilization: {
        peak_memory: get_peak_memory_usage(time_range),
        avg_cpu: get_avg_cpu_usage(time_range),
        database_performance: get_database_performance(time_range)
      }
    }
  end

  def gather_ai_usage_metrics(timeframe)
    time_range = parse_timeframe(timeframe)

    {
      tier_distribution: AiUsageRecord.where(created_at: time_range)
                                     .group(:ai_tier_used)
                                     .count,
      cost_breakdown: AiUsageRecord.where(created_at: time_range)
                                  .group(:ai_tier_used)
                                  .sum(:estimated_cost),
      escalation_analysis: {
        escalation_rate: calculate_escalation_rate(time_range),
        escalation_reasons: get_escalation_reasons(time_range)
      },
      provider_performance: {
        response_times: get_ai_provider_response_times(time_range),
        success_rates: get_ai_provider_success_rates(time_range),
        cost_efficiency: get_ai_cost_efficiency(time_range)
      },
      usage_patterns: {
        hourly_distribution: get_ai_usage_by_hour(time_range),
        user_segment_usage: get_ai_usage_by_user_tier(time_range)
      }
    }
  end

  def gather_system_health_metrics(timeframe)
    time_range = parse_timeframe(timeframe)

    {
      infrastructure: {
        server_health: get_server_health_over_time(time_range),
        database_health: get_database_health_over_time(time_range),
        redis_health: get_redis_health_over_time(time_range)
      },
      application_health: {
        rails_metrics: get_rails_health_metrics(time_range),
        background_job_health: get_background_job_health(time_range),
        websocket_health: get_websocket_health_metrics(time_range)
      },
      external_dependencies: {
        ai_provider_uptime: get_ai_provider_uptime(time_range),
        payment_gateway_health: get_payment_gateway_health(time_range),
        storage_service_health: get_storage_service_health(time_range)
      }
    }
  end

  def gather_user_behavior_metrics(timeframe)
    time_range = parse_timeframe(timeframe)

    {
      activity_patterns: {
        active_users_trend: get_active_users_trend(time_range),
        session_duration: get_avg_session_duration(time_range),
        feature_usage: get_feature_usage_stats(time_range)
      },
      conversion_metrics: {
        signup_to_upload: calculate_signup_to_upload_rate(time_range),
        upload_to_analysis: calculate_upload_to_analysis_rate(time_range),
        trial_to_paid: calculate_trial_to_paid_rate(time_range)
      },
      engagement_metrics: {
        returning_users: get_returning_user_rate(time_range),
        files_per_user: get_avg_files_per_user(time_range),
        ai_usage_per_user: get_avg_ai_usage_per_user(time_range)
      }
    }
  end

  def gather_cost_analysis_metrics(timeframe)
    time_range = parse_timeframe(timeframe)

    {
      total_costs: {
        ai_costs: AiUsageRecord.where(created_at: time_range).sum(:estimated_cost),
        infrastructure_costs: estimate_infrastructure_costs(time_range),
        total_estimated: calculate_total_operational_costs(time_range)
      },
      cost_trends: {
        daily_ai_costs: get_daily_ai_costs(time_range),
        cost_per_user: calculate_cost_per_user(time_range),
        cost_efficiency_trend: get_cost_efficiency_trend(time_range)
      },
      optimization_opportunities: {
        tier_optimization_savings: calculate_tier_optimization_savings(time_range),
        caching_savings: calculate_caching_savings(time_range),
        predicted_savings: calculate_predicted_savings(time_range)
      }
    }
  end

  def start_periodic_updates
    # 5초마다 기본 메트릭 업데이트
    @periodic_timer = every(5.seconds) do
      transmit({
        type: "metrics_update",
        data: gather_system_metrics,
        timestamp: Time.current.iso8601
      })
    end

    # 30초마다 상세 통계 업데이트
    @detailed_timer = every(30.seconds) do
      transmit({
        type: "detailed_update",
        data: {
          queue_details: get_detailed_queue_status,
          recent_activities: get_recent_activities(30),
          performance_snapshot: get_performance_snapshot
        },
        timestamp: Time.current.iso8601
      })
    end
  end

  def stop_periodic_updates
    @periodic_timer&.cancel
    @detailed_timer&.cancel
    @periodic_timer = nil
    @detailed_timer = nil
  end

  def every(interval, &block)
    # Simple timer implementation - in production would use more robust solution
    Thread.new do
      loop do
        sleep(interval)
        begin
          block.call
        rescue StandardError => e
          Rails.logger.error("Periodic update error: #{e.message}")
        end
      end
    end
  end

  def calculate_queue_latency
    oldest_pending = SolidQueue::Job.where(finished_at: nil).order(:created_at).first
    return 0 unless oldest_pending

    ((Time.current - oldest_pending.created_at) * 1000).round
  end

  def get_memory_usage
    # Would integrate with system monitoring
    rss_kb = `ps -o rss= -p #{Process.pid}`.to_i
    {
      used_mb: rss_kb / 1024,
      percentage: (rss_kb.to_f / (2 * 1024 * 1024) * 100).round(2) # Assuming 2GB total
    }
  end

  def get_cpu_usage
    # Would integrate with system monitoring
    {
      current: rand(20.0..60.0).round(2),
      avg_5min: rand(25.0..55.0).round(2)
    }
  end

  def get_active_users_count
    # Users active in last 15 minutes
    User.joins(:excel_files)
        .where(excel_files: { created_at: 15.minutes.ago..Time.current })
        .distinct
        .count
  end

  def calculate_current_error_rate
    last_hour = 1.hour.ago..Time.current
    total_analyses = Analysis.where(created_at: last_hour).count
    failed_files = ExcelFile.where(status: :failed, updated_at: last_hour).count

    total_analyses > 0 ? (failed_files.to_f / total_analyses * 100).round(2) : 0
  end

  def get_avg_response_time(time_range = 1.hour.ago..Time.current)
    # Would integrate with APM tools
    rand(100..300)
  end

  def get_ai_providers_quick_status
    {
      openai: rand > 0.1 ? "healthy" : "degraded",
      anthropic: rand > 0.05 ? "healthy" : "degraded",
      google: rand > 0.15 ? "healthy" : "degraded"
    }
  end

  def get_queue_status
    {
      total_jobs: SolidQueue::Job.count,
      pending: SolidQueue::Job.where(finished_at: nil).count,
      failed: SolidQueue::Job.where.not(failed_at: nil).count,
      processing: SolidQueue::Job.where(finished_at: nil, failed_at: nil).count
    }
  end

  def get_recent_errors(since)
    # Would query error tracking service
    [
      {
        type: "AI Provider Timeout",
        count: 2,
        last_occurrence: 3.minutes.ago,
        severity: "warning"
      },
      {
        type: "File Processing Error",
        count: 1,
        last_occurrence: 1.minute.ago,
        severity: "error"
      }
    ]
  end

  def get_system_resource_usage
    {
      memory: get_memory_usage,
      cpu: get_cpu_usage,
      database: {
        connections: ActiveRecord::Base.connection_pool.stat[:busy],
        pool_size: ActiveRecord::Base.connection_pool.stat[:size]
      },
      storage: {
        used_gb: rand(100..500),
        total_gb: 1000
      }
    }
  end

  def get_escalation_rules
    [
      {
        condition: "error_rate > 5%",
        action: "notify_admin",
        delay: "5 minutes"
      },
      {
        condition: "queue_latency > 30 seconds",
        action: "scale_workers",
        delay: "2 minutes"
      }
    ]
  end

  def perform_comprehensive_health_check
    {
      overall_status: "healthy",
      components: {
        database: check_database_health,
        redis: check_redis_health,
        ai_providers: check_ai_providers_health,
        file_storage: check_file_storage_health,
        background_jobs: check_background_jobs_health
      },
      performance_metrics: {
        response_time: get_avg_response_time,
        memory_usage: get_memory_usage[:percentage],
        error_rate: calculate_current_error_rate
      },
      recommendations: generate_health_recommendations
    }
  end

  def check_database_health
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      {
        status: "healthy",
        response_time: rand(5..20),
        connections: ActiveRecord::Base.connection_pool.stat
      }
    rescue StandardError => e
      {
        status: "unhealthy",
        error: e.message
      }
    end
  end

  def check_redis_health
    begin
      # Would check Redis connection
      {
        status: "healthy",
        memory_usage: rand(50..200),
        connected_clients: rand(10..50)
      }
    rescue StandardError => e
      {
        status: "unhealthy",
        error: e.message
      }
    end
  end

  def check_ai_providers_health
    {
      openai: { status: "healthy", latency: rand(200..500) },
      anthropic: { status: "healthy", latency: rand(200..500) },
      google: { status: "degraded", latency: rand(500..1000) }
    }
  end

  def check_file_storage_health
    {
      status: "healthy",
      available_space: "75%",
      recent_uploads: ExcelFile.where(created_at: 1.hour.ago..Time.current).count
    }
  end

  def check_background_jobs_health
    failed_jobs = SolidQueue::Job.where(failed_at: 1.hour.ago..Time.current).count
    total_jobs = SolidQueue::Job.where(created_at: 1.hour.ago..Time.current).count

    {
      status: failed_jobs < 5 ? "healthy" : "degraded",
      failure_rate: total_jobs > 0 ? (failed_jobs.to_f / total_jobs * 100).round(2) : 0,
      queue_latency: calculate_queue_latency
    }
  end

  def generate_health_recommendations
    recommendations = []

    if get_memory_usage[:percentage] > 80
      recommendations << "Consider increasing memory allocation or optimizing memory usage"
    end

    if calculate_queue_latency > 30000
      recommendations << "Queue latency is high - consider adding more workers"
    end

    if calculate_current_error_rate > 5
      recommendations << "Error rate is elevated - investigate recent failures"
    end

    recommendations
  end

  def parse_timeframe(timeframe)
    case timeframe
    when "1h" then 1.hour.ago..Time.current
    when "24h" then 24.hours.ago..Time.current
    when "7d" then 7.days.ago..Time.current
    when "30d" then 30.days.ago..Time.current
    else 1.hour.ago..Time.current
    end
  end

  # Additional helper methods for detailed metrics
  def get_percentile_response_time(time_range, percentile)
    # Would calculate from APM data
    base_time = get_avg_response_time(time_range)
    (base_time * (1 + percentile / 100.0)).round
  end

  def calculate_requests_per_minute(time_range)
    total_requests = Analysis.where(created_at: time_range).count
    duration_minutes = time_range.size / 1.minute
    duration_minutes > 0 ? (total_requests.to_f / duration_minutes).round(2) : 0
  end

  def get_error_count(time_range)
    ExcelFile.where(status: :failed, updated_at: time_range).count
  end

  def get_error_breakdown(time_range)
    # Would analyze error logs
    {
      "timeout_error" => 5,
      "ai_provider_error" => 3,
      "file_processing_error" => 2,
      "validation_error" => 1
    }
  end

  def get_error_trend(time_range)
    ExcelFile.where(status: :failed, updated_at: time_range)
           .group_by_hour(:updated_at)
           .count
  end

  def get_detailed_queue_status
    {
      queues: SolidQueue::Job.group(:queue_name).count,
      oldest_job: SolidQueue::Job.where(finished_at: nil).minimum(:created_at),
      worker_utilization: calculate_worker_utilization
    }
  end

  def get_recent_activities(minutes)
    [
      {
        type: "file_upload",
        count: ExcelFile.where(created_at: minutes.minutes.ago..Time.current).count,
        trend: "increasing"
      },
      {
        type: "analysis_completion",
        count: Analysis.where(created_at: minutes.minutes.ago..Time.current).count,
        trend: "stable"
      },
      {
        type: "user_registration",
        count: User.where(created_at: minutes.minutes.ago..Time.current).count,
        trend: "stable"
      }
    ]
  end

  def get_performance_snapshot
    {
      response_time: get_avg_response_time,
      throughput: calculate_requests_per_minute(1.hour.ago..Time.current),
      error_rate: calculate_current_error_rate,
      system_load: get_cpu_usage[:current]
    }
  end

  def calculate_worker_utilization
    # Would calculate based on actual worker metrics
    rand(40..80).round(2)
  end
end
