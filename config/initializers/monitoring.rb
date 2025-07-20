# frozen_string_literal: true

# AI 모니터링 설정
Rails.application.config.after_initialize do
  if Rails.env.production? || Rails.env.staging?
    # 모니터링 서비스 초기화
    monitoring = AiIntegration::Services::QualityMonitoringService.instance

    # 알림 설정
    monitoring.configure_alerts({
      critical_quality_threshold: 0.5,
      warning_quality_threshold: 0.65,
      error_rate_threshold: 0.1,
      fallback_rate_threshold: 0.3,

      # 알림 채널
      channels: {
        slack: {
          enabled: ENV["SLACK_WEBHOOK_URL"].present?,
          webhook_url: ENV["SLACK_WEBHOOK_URL"],
          critical_channel: "#alerts-critical",
          warning_channel: "#alerts-warning"
        },
        email: {
          enabled: true,
          recipients: ENV["ALERT_EMAIL_RECIPIENTS"]&.split(",") || [],
          from: "alerts@excelapp.com"
        }
      }
    })

    # 메트릭 수집 간격 설정
    Thread.new do
      loop do
        sleep 60 # 1분마다

        begin
          # 실시간 통계 수집
          stats = monitoring.get_realtime_stats(window: 5.minutes)

          # 대시보드용 Redis에 저장
          Rails.cache.write("ai_monitoring:realtime_stats", stats, expires_in: 2.minutes)

          # 임계값 체크
          if stats[:avg_quality] < 0.65
            Rails.logger.warn("Low average AI response quality: #{stats[:avg_quality]}")
          end

          if stats[:error_rate] > 0.1
            Rails.logger.error("High AI error rate: #{stats[:error_rate]}")
          end

        rescue StandardError => e
          Rails.logger.error("Monitoring stats collection failed: #{e.message}")
        end
      end
    end

    # 자동 튜닝 작업 시작
    Rails.logger.info("Starting AI auto-tuning background job")
    AiAutoTuningJob.perform_later

    # 초기 A/B 테스트 실험 설정
    setup_initial_experiments
  end

  def setup_initial_experiments
    ab_service = AiIntegration::Services::AbTestingService.instance

    # 품질 임계값 실험
    ab_service.create_experiment(
      name: "Quality Threshold Optimization",
      parameter: :quality_threshold,
      variants: [
        { id: "control", value: 0.65, name: "Current (0.65)" },
        { id: "variant_a", value: 0.60, name: "Lower (0.60)" },
        { id: "variant_b", value: 0.70, name: "Higher (0.70)" }
      ],
      allocation: :user_hash,
      traffic_percentage: 30 # 30% 사용자만 실험 참여
    )

    # 캐시 유사도 임계값 실험
    ab_service.create_experiment(
      name: "Cache Similarity Threshold",
      parameter: :cache_similarity_threshold,
      variants: [
        { id: "control", value: 0.85, name: "Current (0.85)" },
        { id: "variant_a", value: 0.80, name: "Lower (0.80)" },
        { id: "variant_b", value: 0.90, name: "Higher (0.90)" }
      ],
      allocation: :user_hash,
      traffic_percentage: 50
    )

    Rails.logger.info("Initial A/B testing experiments created")
  rescue StandardError => e
    Rails.logger.error("Failed to setup initial experiments: #{e.message}")
  end
end

# Prometheus 메트릭 엔드포인트 설정 (선택사항)
if defined?(Prometheus)
  require "prometheus/client"

  # 커스텀 메트릭 정의
  prometheus = Prometheus::Client.registry

  # AI 응답 품질 히스토그램
  AI_RESPONSE_QUALITY = Prometheus::Client::Histogram.new(
    :ai_response_quality,
    docstring: "AI response quality score distribution",
    labels: [ :model, :tier ],
    buckets: [ 0.1, 0.3, 0.5, 0.7, 0.8, 0.9, 0.95, 1.0 ]
  )
  prometheus.register(AI_RESPONSE_QUALITY)

  # AI 응답 시간 히스토그램
  AI_RESPONSE_TIME = Prometheus::Client::Histogram.new(
    :ai_response_time_seconds,
    docstring: "AI response time in seconds",
    labels: [ :model, :tier ],
    buckets: [ 0.1, 0.5, 1, 2, 5, 10, 30, 60 ]
  )
  prometheus.register(AI_RESPONSE_TIME)

  # AI 비용 카운터
  AI_COST_COUNTER = Prometheus::Client::Counter.new(
    :ai_cost_total,
    docstring: "Total AI cost in USD",
    labels: [ :model, :tier ]
  )
  prometheus.register(AI_COST_COUNTER)

  # 폴백 카운터
  AI_FALLBACK_COUNTER = Prometheus::Client::Counter.new(
    :ai_fallback_total,
    docstring: "Total number of AI fallbacks",
    labels: [ :from_tier, :to_tier ]
  )
  prometheus.register(AI_FALLBACK_COUNTER)

  # 캐시 히트율 게이지
  AI_CACHE_HIT_RATE = Prometheus::Client::Gauge.new(
    :ai_cache_hit_rate,
    docstring: "AI semantic cache hit rate"
  )
  prometheus.register(AI_CACHE_HIT_RATE)
end
