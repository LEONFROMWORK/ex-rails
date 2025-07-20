# frozen_string_literal: true

module AiIntegration
  module Services
    # AI 응답 품질을 실시간으로 모니터링하고 메트릭을 수집하는 서비스
    class QualityMonitoringService
      include Singleton

      METRIC_TYPES = {
        response_quality: "ai.response.quality",
        response_time: "ai.response.time",
        token_usage: "ai.token.usage",
        cost: "ai.cost",
        error_rate: "ai.error.rate",
        fallback_rate: "ai.fallback.rate",
        cache_hit_rate: "ai.cache.hit_rate",
        model_usage: "ai.model.usage",
        confidence_distribution: "ai.confidence.distribution"
      }.freeze

      QUALITY_THRESHOLDS = {
        critical: 0.5,
        warning: 0.65,
        good: 0.8,
        excellent: 0.9
      }.freeze

      def initialize
        @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
        @metrics_buffer = []
        @buffer_mutex = Mutex.new
        @alert_cooldown = {}

        # 백그라운드 플러시 시작
        start_background_flush
      end

      # 메트릭 기록
      def record_metric(type, value, tags = {})
        metric = {
          type: METRIC_TYPES[type] || type,
          value: value,
          tags: default_tags.merge(tags),
          timestamp: Time.current.to_f
        }

        @buffer_mutex.synchronize do
          @metrics_buffer << metric
        end

        # 임계값 체크
        check_thresholds(type, value, tags) if type == :response_quality

        # 버퍼가 크면 즉시 플러시
        flush_metrics if @metrics_buffer.size > 100
      end

      # AI 응답 분석 및 기록
      def analyze_response(response_data)
        analysis = {
          model: response_data[:model],
          tier: response_data[:tier],
          confidence: response_data[:confidence_score],
          processing_time: response_data[:processing_time],
          tokens_used: response_data[:credits_used],
          cost: response_data[:cost_breakdown][:current_cost],
          is_fallback: response_data[:is_fallback] || false,
          fallback_chain: response_data[:fallback_details],
          quality_metrics: response_data[:quality_metrics]
        }

        # 개별 메트릭 기록
        record_metric(:response_quality, analysis[:confidence],
                     model: analysis[:model], tier: analysis[:tier])

        record_metric(:response_time, analysis[:processing_time],
                     model: analysis[:model], tier: analysis[:tier])

        record_metric(:token_usage, analysis[:tokens_used],
                     model: analysis[:model])

        record_metric(:cost, analysis[:cost],
                     model: analysis[:model])

        # 폴백 발생시 추가 메트릭
        if analysis[:is_fallback]
          record_metric(:fallback_rate, 1,
                       original_tier: analysis[:fallback_chain]&.first&.dig(:tier),
                       final_tier: analysis[:tier])
        end

        # 실시간 통계 업데이트
        update_realtime_stats(analysis)

        analysis
      end

      # 실시간 대시보드용 통계
      def get_realtime_stats(window: 5.minutes)
        stats = {}

        # Redis에서 최근 통계 가져오기
        stats[:avg_quality] = get_windowed_average("quality", window)
        stats[:avg_response_time] = get_windowed_average("response_time", window)
        stats[:total_requests] = get_windowed_count("requests", window)
        stats[:error_rate] = get_windowed_rate("errors", window)
        stats[:fallback_rate] = get_windowed_rate("fallbacks", window)
        stats[:cache_hit_rate] = get_windowed_rate("cache_hits", window)

        # 모델별 사용량
        stats[:model_distribution] = get_model_distribution(window)

        # 품질 분포
        stats[:quality_distribution] = get_quality_distribution(window)

        # 비용 통계
        stats[:cost_stats] = get_cost_statistics(window)

        # 알림 상태
        stats[:active_alerts] = get_active_alerts

        stats
      end

      # 상세 리포트 생성
      def generate_report(start_time, end_time)
        report = {
          period: {
            start: start_time,
            end: end_time,
            duration_hours: (end_time - start_time) / 3600.0
          },
          summary: generate_summary_stats(start_time, end_time),
          quality_analysis: analyze_quality_trends(start_time, end_time),
          performance_analysis: analyze_performance(start_time, end_time),
          cost_analysis: analyze_costs(start_time, end_time),
          recommendations: generate_recommendations(start_time, end_time)
        }

        # 리포트 저장
        save_report(report)

        report
      end

      # 알림 설정
      def configure_alerts(config)
        @alert_config = config
      end

      private

      def start_background_flush
        Thread.new do
          loop do
            sleep 10
            flush_metrics
          rescue StandardError => e
            Rails.logger.error("Metric flush error: #{e.message}")
          end
        end
      end

      def flush_metrics
        metrics_to_flush = nil

        @buffer_mutex.synchronize do
          return if @metrics_buffer.empty?
          metrics_to_flush = @metrics_buffer.dup
          @metrics_buffer.clear
        end

        # 메트릭 저장 (TimescaleDB, InfluxDB, 또는 Prometheus)
        store_metrics(metrics_to_flush)

        # Redis에 실시간 통계 업데이트
        update_redis_stats(metrics_to_flush)
      end

      def store_metrics(metrics)
        # 배치 삽입을 위한 그룹화
        grouped = metrics.group_by { |m| m[:type] }

        grouped.each do |type, type_metrics|
          # 데이터베이스에 저장 (예: TimescaleDB)
          AiMetric.insert_all(
            type_metrics.map do |metric|
              {
                metric_type: type,
                value: metric[:value],
                tags: metric[:tags].to_json,
                timestamp: Time.at(metric[:timestamp]),
                created_at: Time.current,
                updated_at: Time.current
              }
            end
          )
        end
      rescue StandardError => e
        Rails.logger.error("Failed to store metrics: #{e.message}")
      end

      def update_redis_stats(metrics)
        pipeline = @redis.pipelined do |pipe|
          metrics.each do |metric|
            key_prefix = "ai_metrics:#{metric[:type]}"

            # 시계열 데이터 저장 (1시간 윈도우)
            window_key = "#{key_prefix}:#{Time.at(metric[:timestamp]).strftime('%Y%m%d%H')}"
            pipe.zadd(window_key, metric[:timestamp], metric[:value])
            pipe.expire(window_key, 25.hours)

            # 집계 통계 업데이트
            case metric[:type]
            when METRIC_TYPES[:response_quality]
              update_quality_stats(pipe, metric)
            when METRIC_TYPES[:response_time]
              update_performance_stats(pipe, metric)
            when METRIC_TYPES[:cost]
              update_cost_stats(pipe, metric)
            end
          end
        end
      end

      def update_quality_stats(pipe, metric)
        model = metric[:tags][:model]
        quality = metric[:value]

        # 이동 평균 업데이트
        pipe.lpush("quality:#{model}:recent", quality)
        pipe.ltrim("quality:#{model}:recent", 0, 99)

        # 품질 구간별 카운터
        quality_tier = case quality
        when 0.9..1.0 then "excellent"
        when 0.8..0.9 then "good"
        when 0.65..0.8 then "acceptable"
        else "poor"
        end

        pipe.hincrby("quality:distribution:#{model}", quality_tier, 1)
      end

      def check_thresholds(type, value, tags)
        return unless @alert_config

        # 품질이 임계값 이하로 떨어진 경우
        if type == :response_quality && value < QUALITY_THRESHOLDS[:warning]
          trigger_alert(
            level: value < QUALITY_THRESHOLDS[:critical] ? :critical : :warning,
            message: "AI response quality below threshold: #{value.round(2)}",
            details: {
              model: tags[:model],
              tier: tags[:tier],
              threshold: QUALITY_THRESHOLDS[:warning]
            }
          )
        end
      end

      def trigger_alert(level:, message:, details: {})
        alert_key = "#{level}:#{message.parameterize}"

        # 쿨다운 체크
        return if @alert_cooldown[alert_key] &&
                 Time.current - @alert_cooldown[alert_key] < 5.minutes

        @alert_cooldown[alert_key] = Time.current

        # 알림 전송
        case level
        when :critical
          send_critical_alert(message, details)
        when :warning
          send_warning_alert(message, details)
        end

        # 알림 기록
        record_alert(level, message, details)
      end

      def send_critical_alert(message, details)
        # Slack, PagerDuty, 이메일 등
        Rails.logger.error("CRITICAL ALERT: #{message} - #{details.to_json}")

        # Slack 웹훅 (설정된 경우)
        if ENV["SLACK_WEBHOOK_URL"]
          notify_slack(
            channel: "#alerts-critical",
            message: "🚨 #{message}",
            details: details,
            color: "danger"
          )
        end
      end

      def get_windowed_average(metric, window)
        key = "ai_metrics:#{METRIC_TYPES["response_#{metric}".to_sym]}:#{Time.current.strftime('%Y%m%d%H')}"
        values = @redis.zrange(key, 0, -1)

        return 0 if values.empty?

        values.map(&:to_f).sum / values.size
      end

      def get_model_distribution(window)
        # 모델별 사용 횟수 집계
        distribution = {}

        OpenrouterMultimodalService::MULTIMODAL_MODELS.each do |tier, config|
          model = config[:model]
          count = @redis.get("model_usage:#{model}:#{Time.current.strftime('%Y%m%d%H')}").to_i
          distribution[tier] = {
            model: model,
            count: count,
            percentage: 0 # 나중에 계산
          }
        end

        total = distribution.values.sum { |v| v[:count] }
        distribution.each do |tier, data|
          data[:percentage] = total > 0 ? (data[:count].to_f / total * 100).round(2) : 0
        end

        distribution
      end

      def generate_recommendations(start_time, end_time)
        recommendations = []

        # 품질 기반 추천
        avg_quality = get_period_average("quality", start_time, end_time)
        if avg_quality < 0.7
          recommendations << {
            type: "quality",
            priority: "high",
            message: "평균 응답 품질이 낮습니다. 상위 티어 모델 사용을 고려하세요.",
            metric: avg_quality
          }
        end

        # 비용 기반 추천
        cost_efficiency = calculate_cost_efficiency(start_time, end_time)
        if cost_efficiency < 0.6
          recommendations << {
            type: "cost",
            priority: "medium",
            message: "비용 효율성이 낮습니다. 쿼리 복잡도 분석기 조정을 권장합니다.",
            metric: cost_efficiency
          }
        end

        # 폴백 비율 기반 추천
        fallback_rate = get_period_rate("fallbacks", start_time, end_time)
        if fallback_rate > 0.2
          recommendations << {
            type: "reliability",
            priority: "high",
            message: "폴백 비율이 높습니다. 초기 티어 선택 로직 개선이 필요합니다.",
            metric: fallback_rate
          }
        end

        recommendations
      end

      def default_tags
        {
          environment: Rails.env,
          app_version: Rails.application.config.app_version || "unknown",
          hostname: Socket.gethostname
        }
      end
    end
  end
end
