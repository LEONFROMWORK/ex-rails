# frozen_string_literal: true

module AiIntegration
  module Services
    # 회로 차단기 패턴을 구현하여 연속된 실패 시 서비스를 일시적으로 차단
    class CircuitBreakerService
      STATES = [ :closed, :open, :half_open ].freeze

      attr_reader :state, :failure_count, :last_failure_time

      def initialize(
        failure_threshold: 5,
        timeout: 60.seconds,
        success_threshold: 2,
        redis: Rails.cache
      )
        @failure_threshold = failure_threshold
        @timeout = timeout
        @success_threshold = success_threshold
        @redis = redis
        @state = :closed
        @failure_count = 0
        @success_count = 0
        @last_failure_time = nil
        @mutex = Mutex.new
      end

      # 서비스 호출을 회로 차단기로 래핑
      def call(service_name, &block)
        @mutex.synchronize do
          load_state(service_name)

          case @state
          when :open
            if timeout_expired?
              transition_to_half_open(service_name)
              attempt_call(service_name, &block)
            else
              raise CircuitOpenError.new(
                "Circuit breaker is OPEN for #{service_name}. " \
                "Retry after #{time_until_retry} seconds."
              )
            end
          when :half_open
            attempt_call(service_name, &block)
          when :closed
            attempt_call(service_name, &block)
          end
        end
      end

      # 서비스별 상태 확인
      def status(service_name)
        load_state(service_name)
        {
          state: @state,
          failure_count: @failure_count,
          last_failure: @last_failure_time,
          time_until_retry: @state == :open ? time_until_retry : nil
        }
      end

      # 수동으로 회로 리셋
      def reset(service_name)
        @mutex.synchronize do
          @state = :closed
          @failure_count = 0
          @success_count = 0
          @last_failure_time = nil
          save_state(service_name)
        end
      end

      private

      def attempt_call(service_name, &block)
        result = yield
        record_success(service_name)
        result
      rescue StandardError => e
        record_failure(service_name, e)
        raise
      end

      def record_success(service_name)
        case @state
        when :half_open
          @success_count += 1
          if @success_count >= @success_threshold
            transition_to_closed(service_name)
          end
        when :closed
          # 성공 시 실패 카운트 리셋
          @failure_count = 0 if @failure_count > 0
        end
        save_state(service_name)
      end

      def record_failure(service_name, error)
        @failure_count += 1
        @last_failure_time = Time.current

        Rails.logger.error(
          "Circuit breaker failure for #{service_name}: " \
          "#{error.class} - #{error.message} (#{@failure_count}/#{@failure_threshold})"
        )

        case @state
        when :closed
          if @failure_count >= @failure_threshold
            transition_to_open(service_name)
          end
        when :half_open
          transition_to_open(service_name)
        end

        save_state(service_name)
      end

      def transition_to_open(service_name)
        @state = :open
        @success_count = 0

        Rails.logger.warn("Circuit breaker OPENED for #{service_name}")

        # 알림 전송 (옵션)
        notify_circuit_opened(service_name)
      end

      def transition_to_half_open(service_name)
        @state = :half_open
        @success_count = 0
        @failure_count = 0

        Rails.logger.info("Circuit breaker HALF-OPEN for #{service_name}")
      end

      def transition_to_closed(service_name)
        @state = :closed
        @failure_count = 0
        @success_count = 0
        @last_failure_time = nil

        Rails.logger.info("Circuit breaker CLOSED for #{service_name}")
      end

      def timeout_expired?
        return false unless @last_failure_time

        Time.current - @last_failure_time >= @timeout
      end

      def time_until_retry
        return 0 unless @last_failure_time

        elapsed = Time.current - @last_failure_time
        remaining = @timeout - elapsed
        [ remaining, 0 ].max.to_i
      end

      def load_state(service_name)
        state_data = @redis.read(cache_key(service_name))
        return unless state_data

        @state = state_data[:state].to_sym
        @failure_count = state_data[:failure_count]
        @success_count = state_data[:success_count]
        @last_failure_time = state_data[:last_failure_time]
      end

      def save_state(service_name)
        @redis.write(
          cache_key(service_name),
          {
            state: @state,
            failure_count: @failure_count,
            success_count: @success_count,
            last_failure_time: @last_failure_time
          },
          expires_in: 24.hours
        )
      end

      def cache_key(service_name)
        "circuit_breaker:#{service_name}"
      end

      def notify_circuit_opened(service_name)
        # Slack, PagerDuty 등으로 알림 전송
        # 실제 구현은 프로젝트 요구사항에 따라
      end
    end

    # 회로 차단기가 열려있을 때 발생하는 에러
    class CircuitOpenError < StandardError; end
  end
end
