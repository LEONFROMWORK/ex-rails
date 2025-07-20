# frozen_string_literal: true

module AiIntegration
  module Services
    # 지수 백오프를 사용한 재시도 로직 구현
    class RetryWithBackoffService
      DEFAULT_OPTIONS = {
        max_retries: 3,
        base_delay: 1.0, # seconds
        max_delay: 32.0, # seconds
        exponential_base: 2,
        jitter: true,
        retriable_errors: [
          Net::ReadTimeout,
          Net::OpenTimeout,
          Errno::ECONNREFUSED,
          Errno::ETIMEDOUT,
          HTTParty::ResponseError
          # OpenAI::RateLimitError  # OpenAI gem이 설치되어 있지 않음
        ]
      }.freeze

      def initialize(options = {})
        @options = DEFAULT_OPTIONS.merge(options)
        @logger = Rails.logger
      end

      # 지수 백오프로 작업 실행
      def execute(operation_name, &block)
        attempt = 0
        last_error = nil

        begin
          attempt += 1

          @logger.info("Attempting #{operation_name} (attempt #{attempt}/#{@options[:max_retries] + 1})")

          # 회로 차단기와 통합
          if circuit_breaker
            circuit_breaker.call(operation_name) { yield }
          else
            yield
          end

        rescue *@options[:retriable_errors] => e
          last_error = e

          if attempt <= @options[:max_retries]
            delay = calculate_delay(attempt)

            @logger.warn(
              "#{operation_name} failed with #{e.class}: #{e.message}. " \
              "Retrying in #{delay.round(2)}s (attempt #{attempt}/#{@options[:max_retries] + 1})"
            )

            # 메트릭 기록
            record_retry_metric(operation_name, attempt, e)

            sleep(delay)
            retry
          else
            @logger.error(
              "#{operation_name} failed after #{attempt} attempts. Last error: #{e.class} - #{e.message}"
            )

            # 최종 실패 메트릭
            record_failure_metric(operation_name, attempt, e)

            raise RetryExhaustedError.new(
              "Operation '#{operation_name}' failed after #{attempt} attempts",
              last_error
            )
          end
        end
      end

      # 특정 조건에서만 재시도
      def execute_with_condition(operation_name, retry_condition: nil, &block)
        attempt = 0
        last_result = nil

        loop do
          attempt += 1

          begin
            result = yield(attempt)

            # 재시도 조건 확인
            if retry_condition && retry_condition.call(result, attempt)
              if attempt <= @options[:max_retries]
                delay = calculate_delay(attempt)
                @logger.info(
                  "#{operation_name} needs retry based on condition. " \
                  "Retrying in #{delay.round(2)}s (attempt #{attempt}/#{@options[:max_retries] + 1})"
                )
                sleep(delay)
                next
              else
                @logger.warn("#{operation_name} retry condition not met after #{attempt} attempts")
                return result
              end
            else
              return result
            end

          rescue StandardError => e
            if should_retry?(e) && attempt <= @options[:max_retries]
              delay = calculate_delay(attempt)
              @logger.warn("#{operation_name} error: #{e.message}. Retrying in #{delay.round(2)}s")
              sleep(delay)
            else
              raise
            end
          end
        end
      end

      # 멀티모달 서비스용 특화 재시도
      def execute_with_fallback(operation_name, fallback_chain: [], &block)
        fallback_index = 0

        loop do
          current_operation = fallback_chain[fallback_index] || { name: operation_name, block: block }

          begin
            result = execute(current_operation[:name]) do
              if current_operation[:block]
                current_operation[:block].call
              else
                yield(fallback_index)
              end
            end

            # 품질 체크 (옵션)
            if current_operation[:quality_check]
              quality = current_operation[:quality_check].call(result)
              if quality < (current_operation[:min_quality] || 0.7)
                raise QualityBelowThresholdError.new(
                  "Quality #{quality} below threshold for #{current_operation[:name]}"
                )
              end
            end

            return result

          rescue RetryExhaustedError => e
            fallback_index += 1

            if fallback_index < fallback_chain.length
              @logger.info(
                "Primary operation failed, falling back to: #{fallback_chain[fallback_index][:name]}"
              )
            else
              @logger.error("All operations in fallback chain exhausted")
              raise
            end
          end
        end
      end

      private

      def calculate_delay(attempt)
        # 지수 백오프 계산: base_delay * (exponential_base ^ (attempt - 1))
        delay = @options[:base_delay] * (@options[:exponential_base] ** (attempt - 1))

        # 최대 지연 시간 제한
        delay = [ delay, @options[:max_delay] ].min

        # 지터 추가 (선택적)
        if @options[:jitter]
          jitter_range = delay * 0.1 # ±10% 지터
          delay += (rand * 2 * jitter_range) - jitter_range
        end

        delay
      end

      def should_retry?(error)
        @options[:retriable_errors].any? { |klass| error.is_a?(klass) }
      end

      def circuit_breaker
        @circuit_breaker ||= begin
          if @options[:use_circuit_breaker]
            CircuitBreakerService.new(
              failure_threshold: @options[:circuit_breaker_threshold] || 5,
              timeout: @options[:circuit_breaker_timeout] || 60.seconds
            )
          end
        end
      end

      def record_retry_metric(operation_name, attempt, error)
        # 메트릭 수집 (Prometheus, StatsD 등)
        Rails.logger.tagged("metrics") do
          @logger.info({
            event: "retry_attempt",
            operation: operation_name,
            attempt: attempt,
            error_class: error.class.name,
            timestamp: Time.current
          }.to_json)
        end
      end

      def record_failure_metric(operation_name, attempts, error)
        Rails.logger.tagged("metrics") do
          @logger.error({
            event: "retry_exhausted",
            operation: operation_name,
            total_attempts: attempts,
            error_class: error.class.name,
            error_message: error.message,
            timestamp: Time.current
          }.to_json)
        end
      end
    end

    # 재시도 횟수 초과 에러
    class RetryExhaustedError < StandardError
      attr_reader :original_error

      def initialize(message, original_error = nil)
        super(message)
        @original_error = original_error
      end
    end

    # 품질 임계값 미달 에러
    class QualityBelowThresholdError < StandardError; end
  end
end
