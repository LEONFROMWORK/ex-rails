# frozen_string_literal: true

module Admin
  class AiMonitoringController < ApplicationController
    before_action :authenticate_admin!

    # 실시간 대시보드
    def dashboard
      @realtime_stats = fetch_realtime_stats
      @cache_stats = fetch_cache_stats
      @circuit_breaker_status = fetch_circuit_breaker_status
      @recent_alerts = fetch_recent_alerts

      respond_to do |format|
        format.html # dashboard.html.erb
        format.json { render json: dashboard_data }
      end
    end

    # 상세 리포트
    def report
      start_time = params[:start_time] ? Time.parse(params[:start_time]) : 24.hours.ago
      end_time = params[:end_time] ? Time.parse(params[:end_time]) : Time.current

      @report = monitoring_service.generate_report(start_time, end_time)

      respond_to do |format|
        format.html # report.html.erb
        format.pdf { render pdf: "ai_report_#{Date.current}" }
        format.csv { send_data generate_csv(@report), filename: "ai_report_#{Date.current}.csv" }
      end
    end

    # 실시간 메트릭 API (차트용)
    def metrics
      window = params[:window]&.to_i || 300 # 기본 5분
      metric_type = params[:metric] || "quality"

      data = case metric_type
      when "quality"
               fetch_quality_metrics(window)
      when "performance"
               fetch_performance_metrics(window)
      when "cost"
               fetch_cost_metrics(window)
      when "models"
               fetch_model_distribution(window)
      else
               { error: "Invalid metric type" }
      end

      render json: data
    end

    # 캐시 관리
    def cache_management
      @cache_stats = semantic_cache.stats
      @query_clusters = semantic_cache.find_query_clusters

      if request.post?
        case params[:action_type]
        when "clear_all"
          semantic_cache.invalidate
          flash[:notice] = "전체 캐시가 삭제되었습니다."
        when "clear_pattern"
          semantic_cache.invalidate(params[:pattern])
          flash[:notice] = "패턴 매칭 캐시가 삭제되었습니다."
        end
        redirect_to admin_ai_cache_management_path
      end
    end

    # 회로 차단기 관리
    def circuit_breakers
      @breakers = fetch_all_circuit_breakers

      if request.post? && params[:service_name]
        circuit_breaker = AiIntegration::Services::CircuitBreakerService.new
        circuit_breaker.reset(params[:service_name])
        flash[:notice] = "#{params[:service_name]} 회로 차단기가 리셋되었습니다."
        redirect_to admin_ai_circuit_breakers_path
      end
    end

    # 알림 설정
    def alerts_config
      @current_config = monitoring_service.instance_variable_get(:@alert_config) || {}

      if request.post?
        new_config = {
          critical_quality_threshold: params[:critical_quality].to_f,
          warning_quality_threshold: params[:warning_quality].to_f,
          error_rate_threshold: params[:error_rate].to_f,
          fallback_rate_threshold: params[:fallback_rate].to_f,
          channels: {
            slack: {
              enabled: params[:slack_enabled] == "1",
              webhook_url: params[:slack_webhook],
              critical_channel: params[:slack_critical_channel],
              warning_channel: params[:slack_warning_channel]
            },
            email: {
              enabled: params[:email_enabled] == "1",
              recipients: params[:email_recipients]&.split(",")&.map(&:strip) || []
            }
          }
        }

        monitoring_service.configure_alerts(new_config)
        flash[:notice] = "알림 설정이 업데이트되었습니다."
        redirect_to admin_ai_alerts_config_path
      end
    end

    private

    def monitoring_service
      @monitoring_service ||= AiIntegration::Services::QualityMonitoringService.instance
    end

    def semantic_cache
      @semantic_cache ||= AiIntegration::Services::SemanticCacheService.new
    end

    def fetch_realtime_stats
      Rails.cache.read("ai_monitoring:realtime_stats") || monitoring_service.get_realtime_stats
    end

    def fetch_cache_stats
      semantic_cache.stats
    end

    def fetch_circuit_breaker_status
      services = %w[
        openrouter_google_gemini-flash-1.5
        openrouter_anthropic_claude-3-haiku
        openrouter_openai_gpt-4-vision-preview
      ]

      breaker = AiIntegration::Services::CircuitBreakerService.new

      services.map do |service|
        status = breaker.status(service)
        {
          service: service,
          state: status[:state],
          failure_count: status[:failure_count],
          last_failure: status[:last_failure],
          time_until_retry: status[:time_until_retry]
        }
      end
    end

    def fetch_recent_alerts
      # Redis에서 최근 알림 가져오기
      alerts = []

      redis = Redis.new
      alert_keys = redis.keys("alerts:*").sort.reverse.take(20)

      alert_keys.each do |key|
        alert_data = redis.get(key)
        next unless alert_data

        alerts << JSON.parse(alert_data).merge("key" => key)
      end

      alerts
    rescue StandardError => e
      Rails.logger.error("Failed to fetch alerts: #{e.message}")
      []
    end

    def dashboard_data
      {
        realtime: @realtime_stats,
        cache: @cache_stats,
        circuit_breakers: @circuit_breaker_status,
        alerts: @recent_alerts,
        timestamp: Time.current
      }
    end

    def fetch_quality_metrics(window)
      # 시계열 품질 데이터
      redis = Redis.new
      now = Time.current

      points = []
      (0..window/60).each do |minutes_ago|
        timestamp = now - minutes_ago.minutes
        key = "ai_metrics:ai.response.quality:#{timestamp.strftime('%Y%m%d%H%M')}"

        values = redis.zrange(key, 0, -1).map(&:to_f)
        next if values.empty?

        points << {
          timestamp: timestamp.iso8601,
          avg: values.sum / values.size,
          min: values.min,
          max: values.max,
          count: values.size
        }
      end

      { metric: "quality", window: window, data: points.reverse }
    end

    def fetch_model_distribution(window)
      stats = monitoring_service.get_realtime_stats(window: window.seconds)

      {
        metric: "model_distribution",
        window: window,
        data: stats[:model_distribution]
      }
    end

    def generate_csv(report)
      CSV.generate do |csv|
        # 헤더
        csv << [ "AI Monitoring Report", "#{report[:period][:start]} - #{report[:period][:end]}" ]
        csv << []

        # 요약 통계
        csv << [ "Summary Statistics" ]
        report[:summary].each do |key, value|
          csv << [ key.to_s.humanize, value ]
        end
        csv << []

        # 품질 분석
        csv << [ "Quality Analysis" ]
        report[:quality_analysis].each do |key, value|
          csv << [ key.to_s.humanize, value ]
        end
        csv << []

        # 비용 분석
        csv << [ "Cost Analysis" ]
        report[:cost_analysis].each do |key, value|
          csv << [ key.to_s.humanize, value ]
        end
      end
    end

    def authenticate_admin!
      # 관리자 권한 체크
      redirect_to root_path unless current_user&.admin?
    end
  end
end
