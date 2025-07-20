# frozen_string_literal: true

module AiIntegration
  module Services
    # ML 기반 자동 튜닝으로 AI 시스템 파라미터를 최적화
    class AutoTuningService
      include Singleton

      # 튜닝 가능한 파라미터와 범위
      TUNABLE_PARAMETERS = {
        quality_threshold: {
          range: 0.5..0.9,
          step: 0.05,
          metric: :quality_score,
          optimization: :maximize
        },
        complexity_boundaries: {
          simple_moderate: { range: 20..40, step: 5 },
          moderate_complex: { range: 50..80, step: 5 },
          metric: :routing_accuracy,
          optimization: :maximize
        },
        cache_ttl: {
          range: 1..48, # hours
          step: 1,
          metric: :cache_efficiency,
          optimization: :maximize
        },
        retry_delays: {
          base_delay: { range: 0.5..3.0, step: 0.5 },
          max_delay: { range: 5..30, step: 5 },
          metric: :recovery_rate,
          optimization: :maximize
        }
      }.freeze

      def initialize
        @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
        @monitoring = QualityMonitoringService.instance
        @current_parameters = load_current_parameters
        @learning_rate = 0.1
        @exploration_rate = 0.15 # 15% 탐색, 85% 활용
      end

      # 자동 튜닝 실행
      def run_tuning_cycle
        Rails.logger.info("Starting auto-tuning cycle")

        # 1. 현재 성능 메트릭 수집
        current_metrics = collect_performance_metrics

        # 2. 시간대별 패턴 분석
        temporal_patterns = analyze_temporal_patterns

        # 3. 각 파라미터별 최적화
        TUNABLE_PARAMETERS.each do |param_name, config|
          optimize_parameter(param_name, config, current_metrics, temporal_patterns)
        end

        # 4. 파라미터 간 상호작용 분석
        analyze_parameter_interactions

        # 5. 학습된 패턴 저장
        save_learned_patterns(temporal_patterns)

        Rails.logger.info("Auto-tuning cycle completed")
      end

      # 시간대별 최적 파라미터 제공
      def get_optimized_parameters(context = {})
        # 현재 시간대
        hour = Time.current.hour
        day_of_week = Time.current.wday

        # 학습된 시간대별 패턴 적용
        temporal_params = get_temporal_parameters(hour, day_of_week)

        # 컨텍스트 기반 조정
        context_adjusted = adjust_for_context(temporal_params, context)

        # A/B 테스트 중인 파라미터는 A/B 서비스에서 가져오기
        final_params = apply_ab_test_overrides(context_adjusted, context[:user_id])

        final_params
      end

      # 성능 예측
      def predict_performance(parameter_changes)
        # 과거 데이터 기반 성능 예측
        historical_data = load_historical_performance

        predictions = {}

        parameter_changes.each do |param, new_value|
          # 유사한 과거 설정 찾기
          similar_configs = find_similar_configurations(param, new_value, historical_data)

          if similar_configs.any?
            # 가중 평균으로 예측
            predictions[param] = weighted_performance_average(similar_configs, new_value)
          else
            # 선형 보간 또는 ML 모델 사용
            predictions[param] = interpolate_performance(param, new_value, historical_data)
          end
        end

        predictions
      end

      # 이상 탐지 및 자동 조정
      def detect_and_adjust_anomalies
        # 최근 5분간 메트릭
        recent_metrics = @monitoring.get_realtime_stats(window: 5.minutes)

        # 이상 탐지
        anomalies = detect_anomalies(recent_metrics)

        if anomalies.any?
          Rails.logger.warn("Detected anomalies: #{anomalies}")

          # 자동 조정
          anomalies.each do |anomaly|
            auto_adjust_for_anomaly(anomaly)
          end
        end
      end

      private

      def collect_performance_metrics
        # 다양한 성능 메트릭 수집
        {
          quality_score: calculate_average_quality,
          routing_accuracy: calculate_routing_accuracy,
          cache_efficiency: calculate_cache_efficiency,
          recovery_rate: calculate_recovery_rate,
          cost_per_request: calculate_average_cost,
          user_satisfaction: estimate_user_satisfaction
        }
      end

      def analyze_temporal_patterns
        # 시간대별 패턴 분석
        patterns = {
          hourly: analyze_hourly_patterns,
          daily: analyze_daily_patterns,
          weekly: analyze_weekly_patterns
        }

        # 특별한 패턴 감지
        patterns[:peak_hours] = detect_peak_hours(patterns[:hourly])
        patterns[:weekend_pattern] = detect_weekend_pattern(patterns[:daily])

        patterns
      end

      def optimize_parameter(param_name, config, current_metrics, temporal_patterns)
        # Epsilon-Greedy 전략
        if rand < @exploration_rate
          # 탐색: 새로운 값 시도
          explore_parameter(param_name, config)
        else
          # 활용: 최적값 방향으로 조정
          exploit_parameter(param_name, config, current_metrics)
        end
      end

      def explore_parameter(param_name, config)
        current_value = @current_parameters[param_name]

        # 랜덤하게 새 값 선택
        if config[:range]
          new_value = random_value_in_range(config[:range], config[:step])
        else
          # 복합 파라미터의 경우
          new_value = {}
          config.each do |sub_param, sub_config|
            next unless sub_config.is_a?(Hash) && sub_config[:range]
            new_value[sub_param] = random_value_in_range(sub_config[:range], sub_config[:step])
          end
        end

        # 임시 적용 및 성능 측정
        apply_and_measure(param_name, new_value)
      end

      def exploit_parameter(param_name, config, current_metrics)
        # 그라디언트 기반 최적화
        gradient = estimate_gradient(param_name, config, current_metrics)

        current_value = @current_parameters[param_name]

        if config[:range]
          # 단일 값 파라미터
          new_value = current_value + (@learning_rate * gradient * config[:step])
          new_value = clamp_value(new_value, config[:range])
        else
          # 복합 파라미터
          new_value = update_complex_parameter(current_value, gradient, config)
        end

        @current_parameters[param_name] = new_value
        save_current_parameters
      end

      def estimate_gradient(param_name, config, current_metrics)
        # 유한 차분법으로 그라디언트 추정
        metric_name = config[:metric]
        current_metric = current_metrics[metric_name]

        # 작은 변화 적용
        delta = config[:step] || 0.1

        # 양방향 차분
        plus_metric = measure_with_change(param_name, delta, metric_name)
        minus_metric = measure_with_change(param_name, -delta, metric_name)

        gradient = (plus_metric - minus_metric) / (2 * delta)

        # 최적화 방향 고려
        config[:optimization] == :minimize ? -gradient : gradient
      end

      def analyze_parameter_interactions
        # 파라미터 간 상호작용 분석
        interactions = {}

        # 상관관계 매트릭스 계산
        parameter_names = TUNABLE_PARAMETERS.keys

        parameter_names.combination(2).each do |param1, param2|
          correlation = calculate_parameter_correlation(param1, param2)

          if correlation.abs > 0.5 # 강한 상관관계
            interactions["#{param1}_#{param2}"] = {
              correlation: correlation,
              recommendation: generate_interaction_recommendation(param1, param2, correlation)
            }
          end
        end

        apply_interaction_adjustments(interactions)
      end

      def get_temporal_parameters(hour, day_of_week)
        # 학습된 시간대별 최적 파라미터 로드
        temporal_key = "tuning:temporal:#{day_of_week}:#{hour}"

        cached_params = @redis.get(temporal_key)
        return JSON.parse(cached_params, symbolize_names: true) if cached_params

        # 기본값 with 시간대별 조정
        params = @current_parameters.dup

        # 피크 시간대 조정
        if peak_hour?(hour, day_of_week)
          params[:quality_threshold] -= 0.05 # 품질 기준 약간 완화
          params[:cache_ttl] *= 1.5 # 캐시 시간 연장
        end

        # 야간 시간대 조정
        if night_hour?(hour)
          params[:quality_threshold] += 0.05 # 품질 기준 상향
          params[:retry_delays][:max_delay] *= 0.5 # 재시도 지연 감소
        end

        params
      end

      def detect_anomalies(metrics)
        anomalies = []

        # 품질 점수 이상
        if metrics[:avg_quality] < 0.5
          anomalies << {
            type: :low_quality,
            severity: :critical,
            value: metrics[:avg_quality]
          }
        end

        # 오류율 이상
        if metrics[:error_rate] > 0.2
          anomalies << {
            type: :high_error_rate,
            severity: :critical,
            value: metrics[:error_rate]
          }
        end

        # 응답 시간 이상
        avg_response_time = metrics[:avg_response_time] || 0
        if avg_response_time > 10 # 10초 초과
          anomalies << {
            type: :slow_response,
            severity: :warning,
            value: avg_response_time
          }
        end

        # 비용 급증
        cost_spike = detect_cost_spike(metrics)
        if cost_spike
          anomalies << cost_spike
        end

        anomalies
      end

      def auto_adjust_for_anomaly(anomaly)
        case anomaly[:type]
        when :low_quality
          # 품질 임계값 낮추고 상위 티어 사용 증가
          @current_parameters[:quality_threshold] = [ 0.5, anomaly[:value] - 0.1 ].max
          broadcast_parameter_update(:quality_threshold, @current_parameters[:quality_threshold])

        when :high_error_rate
          # 재시도 설정 조정
          @current_parameters[:retry_delays][:max_delay] *= 1.5
          @current_parameters[:retry_delays][:base_delay] *= 1.2

        when :slow_response
          # 캐시 적극 활용
          @current_parameters[:cache_ttl] *= 2
          @current_parameters[:cache_similarity_threshold] -= 0.05

        when :cost_spike
          # 비용 절감 모드
          enable_cost_saving_mode
        end

        save_current_parameters

        # 조정 내역 기록
        log_anomaly_adjustment(anomaly, @current_parameters)
      end

      def enable_cost_saving_mode
        # 일시적으로 저비용 모델 우선 사용
        @redis.setex("tuning:cost_saving_mode", 1.hour, "true")

        # 품질 기준 완화
        @current_parameters[:quality_threshold] *= 0.9

        # 캐시 활용 극대화
        @current_parameters[:cache_similarity_threshold] -= 0.1
      end

      def calculate_routing_accuracy
        # 라우팅 정확도: 첫 시도에서 적절한 모델을 선택한 비율
        total_requests = @redis.get("routing:total_requests").to_i
        first_try_success = @redis.get("routing:first_try_success").to_i

        return 0 if total_requests == 0

        first_try_success.to_f / total_requests
      end

      def calculate_cache_efficiency
        # 캐시 효율성: 히트율 * 평균 시간 절약
        cache_stats = SemanticCacheService.new.stats
        hit_rate = cache_stats[:hit_rate] / 100.0

        # 평균 시간 절약 계산
        cached_time = 0.1 # 100ms
        avg_api_time = 3.0 # 3초
        time_saving = (avg_api_time - cached_time) / avg_api_time

        hit_rate * time_saving
      end

      def calculate_recovery_rate
        # 복구율: 재시도로 성공한 비율
        total_retries = @redis.get("retry:total_attempts").to_i
        successful_retries = @redis.get("retry:successful_recoveries").to_i

        return 0 if total_retries == 0

        successful_retries.to_f / total_retries
      end

      def estimate_user_satisfaction
        # 사용자 만족도 추정 (복합 지표)
        quality = calculate_average_quality
        speed = 1.0 / (1.0 + calculate_average_response_time)
        reliability = 1.0 - calculate_error_rate

        # 가중 평균
        (quality * 0.5 + speed * 0.3 + reliability * 0.2).round(3)
      end

      def save_learned_patterns(patterns)
        @redis.setex("tuning:learned_patterns", 7.days, patterns.to_json)

        # 시간대별 최적 파라미터 저장
        patterns[:hourly].each do |hour, hour_data|
          if hour_data[:optimal_params]
            @redis.setex(
              "tuning:hourly_optimal:#{hour}",
              1.day,
              hour_data[:optimal_params].to_json
            )
          end
        end
      end

      def load_current_parameters
        stored = @redis.get("tuning:current_parameters")
        return JSON.parse(stored, symbolize_names: true) if stored

        # 기본값
        {
          quality_threshold: 0.65,
          complexity_boundaries: { simple_moderate: 30, moderate_complex: 70 },
          cache_ttl: 24,
          retry_delays: { base_delay: 1.0, max_delay: 8.0 }
        }
      end

      def save_current_parameters
        @redis.set("tuning:current_parameters", @current_parameters.to_json)
      end

      def broadcast_parameter_update(param_name, new_value)
        # 실시간으로 시스템에 파라미터 업데이트 전파
        Rails.cache.write("ai_config:#{param_name}", new_value, expires_in: 1.hour)

        # 이벤트 발행 (ActionCable, Redis Pub/Sub 등)
        ActionCable.server.broadcast("ai_config_channel", {
          parameter: param_name,
          value: new_value,
          timestamp: Time.current
        })
      end
    end
  end
end
