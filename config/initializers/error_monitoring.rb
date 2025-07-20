# frozen_string_literal: true

# 에러 모니터링 및 알림 시스템
module ErrorMonitoring
  # 에러 심각도 분류
  SEVERITY_LEVELS = {
    critical: %w[
      NoMemoryError
      SecurityError
      SystemStackError
      LoadError
    ],
    high: %w[
      StandardError
      ActiveRecord::RecordInvalid
      ActiveRecord::RecordNotFound
      ActionController::ParameterMissing
      Common::Errors::BusinessError
    ],
    medium: %w[
      ActiveRecord::RecordNotUnique
      ActionController::BadRequest
      ArgumentError
      TypeError
    ],
    low: %w[
      ActiveRecord::RecordNotFound
      ActionController::RoutingError
    ]
  }.freeze

  # 에러 발생률 임계값
  ERROR_RATE_THRESHOLDS = {
    critical: 1.0,   # 1% 이상
    high: 2.0,       # 2% 이상
    medium: 5.0,     # 5% 이상
    low: 10.0        # 10% 이상
  }.freeze

  # 글로벌 에러 핸들러
  class ErrorHandler
    include Singleton

    def initialize
      @error_counts = {}
      @last_reset = Time.current
      @notification_cooldowns = {}
    end

    # 에러 기록 및 분석
    def record_error(exception, context = {})
      error_data = {
        class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace&.first(10),
        context: context,
        severity: determine_severity(exception),
        timestamp: Time.current.iso8601,
        request_id: context[:request_id] || Current.request_id,
        user_id: context[:user_id] || Current.user&.id,
        environment: Rails.env
      }

      # 에러 카운트 증가
      increment_error_count(error_data[:class])

      # 로깅
      log_error(error_data)

      # 캐시에 저장
      store_error_data(error_data)

      # 알림 처리
      handle_notifications(error_data)

      # 에러율 모니터링
      check_error_rate

      error_data
    end

    # 에러 통계 조회
    def get_error_stats(timeframe = "1h")
      cache_key = "error_stats:#{timeframe}"

      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        calculate_error_statistics(timeframe)
      end
    end

    # 에러 트렌드 분석
    def get_error_trends(hours = 24)
      trends = {}

      (0...hours).each do |hour_offset|
        timestamp = (Time.current - hour_offset.hours).beginning_of_hour
        key = "errors:#{timestamp.to_i}"

        hourly_errors = Rails.cache.read(key) || []
        trends[timestamp.iso8601] = {
          total: hourly_errors.count,
          by_severity: group_by_severity(hourly_errors),
          by_class: group_by_class(hourly_errors)
        }
      end

      trends
    end

    # 특정 에러 상세 정보
    def get_error_details(error_class, limit = 50)
      key = "error_details:#{error_class}"
      Rails.cache.read(key)&.last(limit) || []
    end

    # 에러 발생률 계산
    def calculate_error_rate(timeframe = "1h")
      error_stats = get_error_stats(timeframe)
      request_stats = PerformanceMonitoring.get_performance_stats(timeframe)

      total_errors = error_stats[:total_errors] || 0
      total_requests = request_stats.dig(:requests, :total_requests) || 1

      (total_errors.to_f / total_requests * 100).round(2)
    end

    private

    def determine_severity(exception)
      exception_class = exception.class.name

      SEVERITY_LEVELS.each do |level, classes|
        return level if classes.include?(exception_class)
      end

      # 기본값은 medium
      :medium
    end

    def increment_error_count(error_class)
      reset_counts_if_needed
      @error_counts[error_class] ||= 0
      @error_counts[error_class] += 1
    end

    def reset_counts_if_needed
      if Time.current - @last_reset > 1.hour
        @error_counts.clear
        @last_reset = Time.current
      end
    end

    def log_error(error_data)
      severity = error_data[:severity]

      case severity
      when :critical
        Rails.logger.fatal(format_error_message(error_data))
      when :high
        Rails.logger.error(format_error_message(error_data))
      when :medium
        Rails.logger.warn(format_error_message(error_data))
      else
        Rails.logger.info(format_error_message(error_data))
      end
    end

    def format_error_message(error_data)
      "[#{error_data[:severity].upcase}] #{error_data[:class]}: #{error_data[:message]} " \
      "(Request: #{error_data[:request_id]}, User: #{error_data[:user_id]}) " \
      "Context: #{error_data[:context].inspect}"
    end

    def store_error_data(error_data)
      # 시간별 에러 데이터 저장
      hour_key = "errors:#{Time.current.beginning_of_hour.to_i}"
      current_errors = Rails.cache.read(hour_key) || []
      current_errors << error_data
      Rails.cache.write(hour_key, current_errors, expires_in: 48.hours)

      # 에러 클래스별 상세 데이터 저장
      detail_key = "error_details:#{error_data[:class]}"
      error_details = Rails.cache.read(detail_key) || []
      error_details << error_data
      # 최근 100개만 유지
      error_details = error_details.last(100)
      Rails.cache.write(detail_key, error_details, expires_in: 24.hours)
    end

    def handle_notifications(error_data)
      severity = error_data[:severity]
      error_class = error_data[:class]

      # Cooldown 체크 (같은 에러를 너무 자주 알리지 않음)
      cooldown_key = "#{error_class}:#{severity}"
      last_notification = @notification_cooldowns[cooldown_key]

      cooldown_period = case severity
      when :critical then 5.minutes
      when :high then 15.minutes
      when :medium then 1.hour
      else 4.hours
      end

      return if last_notification && Time.current - last_notification < cooldown_period

      @notification_cooldowns[cooldown_key] = Time.current

      # 알림 전송
      send_error_notification(error_data)
    end

    def send_error_notification(error_data)
      return unless Rails.env.production?

      # Slack, 이메일, PagerDuty 등 외부 서비스로 알림
      notification_data = {
        title: "🚨 #{error_data[:severity].upcase} Error Detected",
        error_class: error_data[:class],
        message: error_data[:message],
        frequency: @error_counts[error_data[:class]],
        environment: Rails.env,
        time: error_data[:timestamp],
        context: error_data[:context]
      }

      case error_data[:severity]
      when :critical
        send_critical_alert(notification_data)
      when :high
        send_high_priority_alert(notification_data)
      else
        send_standard_alert(notification_data)
      end
    end

    def send_critical_alert(data)
      # 즉시 알림 (PagerDuty, SMS 등)
      Rails.logger.fatal("CRITICAL ALERT: #{data[:error_class]} - #{data[:message]}")
    end

    def send_high_priority_alert(data)
      # 높은 우선순위 알림 (Slack 멘션, 이메일 등)
      Rails.logger.error("HIGH PRIORITY ALERT: #{data[:error_class]} - #{data[:message]}")
    end

    def send_standard_alert(data)
      # 일반 알림 (Slack 채널 등)
      Rails.logger.warn("STANDARD ALERT: #{data[:error_class]} - #{data[:message]}")
    end

    def check_error_rate
      current_rate = calculate_error_rate("1h")

      alert_level = case current_rate
      when 0...ERROR_RATE_THRESHOLDS[:critical]
                     nil
      when ERROR_RATE_THRESHOLDS[:critical]...ERROR_RATE_THRESHOLDS[:high]
                     :critical
      when ERROR_RATE_THRESHOLDS[:high]...ERROR_RATE_THRESHOLDS[:medium]
                     :high
      when ERROR_RATE_THRESHOLDS[:medium]...ERROR_RATE_THRESHOLDS[:low]
                     :medium
      else
                     :low
      end

      if alert_level
        send_error_rate_alert(current_rate, alert_level)
      end
    end

    def send_error_rate_alert(rate, level)
      cooldown_key = "error_rate:#{level}"
      return if @notification_cooldowns[cooldown_key] &&
                Time.current - @notification_cooldowns[cooldown_key] < 30.minutes

      @notification_cooldowns[cooldown_key] = Time.current

      Rails.logger.error(
        "ERROR RATE ALERT [#{level.upcase}]: Current error rate is #{rate}% " \
        "(Threshold: #{ERROR_RATE_THRESHOLDS[level]}%)"
      )
    end

    def calculate_error_statistics(timeframe)
      minutes = case timeframe
      when "1h" then 60
      when "24h" then 1440
      when "7d" then 10080
      else 60
      end

      all_errors = collect_errors_for_timeframe(minutes)

      {
        total_errors: all_errors.count,
        errors_by_severity: group_by_severity(all_errors),
        errors_by_class: group_by_class(all_errors),
        top_errors: get_top_errors(all_errors),
        error_rate: calculate_error_rate(timeframe),
        unique_errors: all_errors.map { |e| e[:class] }.uniq.count
      }
    end

    def collect_errors_for_timeframe(minutes)
      hours = (minutes / 60.0).ceil
      all_errors = []

      (0...hours).each do |hour_offset|
        hour_key = "errors:#{(Time.current - hour_offset.hours).beginning_of_hour.to_i}"
        hourly_errors = Rails.cache.read(hour_key) || []

        # 분 단위로 필터링
        cutoff_time = Time.current - minutes.minutes
        filtered_errors = hourly_errors.select do |error|
          Time.parse(error[:timestamp]) > cutoff_time
        end

        all_errors.concat(filtered_errors)
      end

      all_errors
    end

    def group_by_severity(errors)
      errors.group_by { |e| e[:severity] }
            .transform_values(&:count)
    end

    def group_by_class(errors)
      errors.group_by { |e| e[:class] }
            .transform_values(&:count)
            .sort_by { |_, count| -count }
            .first(10)
            .to_h
    end

    def get_top_errors(errors)
      errors.group_by { |e| [ e[:class], e[:message] ] }
            .map do |key, occurrences|
              {
                class: key[0],
                message: key[1],
                count: occurrences.count,
                first_seen: occurrences.map { |e| e[:timestamp] }.min,
                last_seen: occurrences.map { |e| e[:timestamp] }.max,
                severity: occurrences.first[:severity]
              }
            end
            .sort_by { |e| -e[:count] }
            .first(10)
    end
  end

  # Rails 에러 핸들러 등록
  Rails.application.config.exceptions_app = lambda do |env|
    exception = env["action_dispatch.exception"]
    request = ActionDispatch::Request.new(env)

    context = {
      request_id: request.uuid,
      path: request.path,
      method: request.method,
      params: request.params.except("controller", "action"),
      user_agent: request.user_agent,
      ip: request.remote_ip
    }

    ErrorHandler.instance.record_error(exception, context)

    # 기본 에러 페이지 반환
    ActionDispatch::PublicExceptions.new(Rails.public_path).call(env)
  end
end

# ApplicationController에서 사용할 에러 핸들링 concern
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
    rescue_from Common::Errors::BusinessError, with: :handle_business_error
  end

  private

  def handle_standard_error(exception)
    context = {
      controller: controller_name,
      action: action_name,
      params: params.except("controller", "action").to_unsafe_h,
      user_id: current_user&.id
    }

    ErrorMonitoring::ErrorHandler.instance.record_error(exception, context)

    if Rails.env.development?
      raise exception
    else
      render_error_response(exception, :internal_server_error)
    end
  end

  def handle_not_found(exception)
    render_error_response(exception, :not_found)
  end

  def handle_parameter_missing(exception)
    render_error_response(exception, :bad_request)
  end

  def handle_business_error(exception)
    render_error_response(exception, :unprocessable_entity)
  end

  def render_error_response(exception, status)
    respond_to do |format|
      format.html { render "errors/generic", status: status }
      format.json do
        render json: {
          error: {
            type: exception.class.name,
            message: sanitize_error_message(exception.message),
            status: status
          }
        }, status: status
      end
    end
  end

  def sanitize_error_message(message)
    # 사용자에게 노출하기에 안전한 에러 메시지만 반환
    case message
    when /database/i, /connection/i, /timeout/i
      "시스템에 일시적인 문제가 발생했습니다. 잠시 후 다시 시도해주세요."
    when /not found/i
      "요청하신 리소스를 찾을 수 없습니다."
    when /unauthorized/i, /forbidden/i
      "이 작업을 수행할 권한이 없습니다."
    else
      message.length > 100 ? "처리 중 오류가 발생했습니다." : message
    end
  end
end

Rails.logger.info "Error monitoring system initialized"
