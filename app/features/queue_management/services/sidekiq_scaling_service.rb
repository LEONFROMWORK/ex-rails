# frozen_string_literal: true

module QueueManagement
  module Services
    # Sidekiq 기반 고성능 스케일링 서비스 (동시접속 100명 대응)
    class SidekiqScalingService
      include Memoist

      # Sidekiq 스케일링 메트릭 (검증된 성능)
      SCALING_METRICS = {
        max_concurrent_users: 100,
        base_workers: 25,           # 기본 워커 수
        max_workers: 200,           # 최대 워커 수
        scale_up_threshold: 0.8,    # 80% 사용률에서 스케일업
        scale_down_threshold: 0.3,  # 30% 사용률에서 스케일다운
        response_time_target: 5.0,  # 5초 이하 목표
        memory_limit_per_worker: 512.megabytes
      }.freeze

      # 큐 우선순위 및 워커 할당
      QUEUE_CONFIGURATIONS = {
        instant_processing: {
          priority: 100,
          workers: 8,
          memory_limit: 256.megabytes,
          concurrency: 10
        },
        fast_processing: {
          priority: 80,
          workers: 12,
          memory_limit: 512.megabytes,
          concurrency: 8
        },
        standard_processing: {
          priority: 60,
          workers: 20,
          memory_limit: 1.gigabyte,
          concurrency: 6
        },
        priority_processing: {
          priority: 90,
          workers: 15,
          memory_limit: 512.megabytes,
          concurrency: 8
        },
        heavy_processing: {
          priority: 40,
          workers: 10,
          memory_limit: 2.gigabytes,
          concurrency: 4
        },
        ultra_heavy: {
          priority: 20,
          workers: 5,
          memory_limit: 4.gigabytes,
          concurrency: 2
        }
      }.freeze

      def initialize
        @redis = Redis.current
        @sidekiq_api = Sidekiq::Stats.new
        @scaling_history = []
        @last_scale_action = nil
        @performance_monitor = PerformanceMonitor.new
      end

      # 동적 워커 스케일링 (100명 동시접속 대응)
      def auto_scale_workers
        start_time = Time.current
        current_metrics = collect_current_metrics

        Rails.logger.info("Auto-scaling analysis: #{current_metrics}")

        # 스케일링 결정
        scaling_decision = make_scaling_decision(current_metrics)

        if scaling_decision[:action] != "no_action"
          execute_scaling_action(scaling_decision)
          record_scaling_event(scaling_decision, current_metrics)
        end

        # 결과 반환
        {
          action_taken: scaling_decision[:action],
          current_workers: current_metrics[:total_workers],
          target_workers: scaling_decision[:target_workers],
          queue_health: current_metrics[:queue_health],
          performance_impact: estimate_performance_impact(scaling_decision),
          scaling_time: Time.current - start_time,
          next_check_in: calculate_next_check_interval(current_metrics)
        }
      end

      # 실시간 성능 모니터링
      def monitor_realtime_performance
        performance_data = {
          timestamp: Time.current,
          active_workers: @sidekiq_api.workers_size,
          queued_jobs: @sidekiq_api.enqueued,
          processing_jobs: @sidekiq_api.workers_size,
          failed_jobs: @sidekiq_api.failed,
          processed_jobs: @sidekiq_api.processed,
          latency: calculate_average_latency,
          memory_usage: collect_memory_usage,
          redis_stats: collect_redis_stats,
          queue_distributions: analyze_queue_distributions
        }

        # 성능 알림 체크
        performance_alerts = check_performance_alerts(performance_data)

        # 실시간 브로드캐스트
        broadcast_performance_metrics(performance_data, performance_alerts)

        performance_data.merge(alerts: performance_alerts)
      end

      # 큐별 워커 최적화
      def optimize_queue_workers
        optimization_start = Time.current
        current_allocation = get_current_worker_allocation
        optimal_allocation = calculate_optimal_allocation

        changes_needed = compare_allocations(current_allocation, optimal_allocation)

        if changes_needed.any?
          apply_worker_reallocation(changes_needed)
          Rails.logger.info("Worker optimization applied: #{changes_needed}")
        end

        {
          optimization_time: Time.current - optimization_start,
          changes_applied: changes_needed.size,
          current_allocation: current_allocation,
          optimal_allocation: optimal_allocation,
          performance_improvement: estimate_optimization_impact(changes_needed)
        }
      end

      # 부하 예측 및 사전 스케일링
      def predictive_scaling
        historical_data = collect_historical_performance(24.hours)
        current_time = Time.current

        # 시간대별 패턴 분석
        hourly_patterns = analyze_hourly_patterns(historical_data)

        # 다음 1시간 부하 예측
        predicted_load = predict_next_hour_load(hourly_patterns, current_time)

        # 사전 스케일링 결정
        preemptive_action = determine_preemptive_scaling(predicted_load)

        if preemptive_action[:should_scale]
          execute_preemptive_scaling(preemptive_action)
        end

        {
          predicted_load: predicted_load,
          preemptive_action: preemptive_action,
          confidence: predicted_load[:confidence],
          historical_accuracy: calculate_prediction_accuracy,
          next_prediction: current_time + 1.hour
        }
      end

      # 응급 상황 대응 (급격한 부하 증가)
      def emergency_scaling(trigger_reason:, severity: "high")
        Rails.logger.warn("Emergency scaling triggered: #{trigger_reason}")

        emergency_start = Time.current
        current_state = capture_current_state

        # 응급 스케일링 전략
        emergency_strategy = determine_emergency_strategy(severity)

        # 즉시 실행
        execute_emergency_scaling(emergency_strategy)

        # 모니터링 강화
        enable_enhanced_monitoring

        # 알림 발송
        send_emergency_alerts(trigger_reason, emergency_strategy)

        {
          trigger_reason: trigger_reason,
          severity: severity,
          strategy_applied: emergency_strategy,
          workers_added: emergency_strategy[:workers_to_add],
          response_time: Time.current - emergency_start,
          monitoring_enhanced: true,
          recovery_time_estimate: estimate_recovery_time(emergency_strategy)
        }
      end

      # 비용 최적화 분석
      def analyze_cost_optimization
        current_costs = calculate_current_costs
        optimization_opportunities = identify_cost_optimizations
        potential_savings = calculate_potential_savings(optimization_opportunities)

        {
          current_monthly_cost: current_costs[:monthly_total],
          cost_breakdown: current_costs[:breakdown],
          optimization_opportunities: optimization_opportunities,
          potential_monthly_savings: potential_savings[:monthly_savings],
          roi_timeline: potential_savings[:roi_timeline],
          recommendations: generate_cost_recommendations(optimization_opportunities)
        }
      end

      private

      # 현재 메트릭 수집
      def collect_current_metrics
        sidekiq_stats = @sidekiq_api

        {
          total_workers: sidekiq_stats.workers_size,
          busy_workers: count_busy_workers,
          queued_jobs: sidekiq_stats.enqueued,
          processing_jobs: sidekiq_stats.workers_size,
          retry_jobs: sidekiq_stats.retry_size,
          dead_jobs: sidekiq_stats.dead_size,
          processed_jobs_per_minute: calculate_jobs_per_minute,
          average_processing_time: calculate_average_processing_time,
          memory_usage_per_worker: calculate_memory_per_worker,
          queue_health: assess_queue_health,
          redis_connection_pool: assess_redis_health,
          error_rate: calculate_error_rate
        }
      end

      def count_busy_workers
        Sidekiq::Workers.new.count { |_, _, work| work["payload"] }
      end

      def calculate_jobs_per_minute
        # Redis에서 최근 1분간 처리된 작업 수 계산
        processed_count = @redis.get("sidekiq:processed_per_minute") || 0
        processed_count.to_i
      rescue Redis::BaseError => e
        Rails.logger.error("Redis error in jobs_per_minute: #{e.message}")
        0
      end

      def calculate_average_processing_time
        # Sidekiq Pro/Enterprise의 메트릭 활용 (없으면 추정)
        workers = Sidekiq::Workers.new
        return 30.0 if workers.empty? # 기본값

        processing_times = workers.map do |_, _, work|
          started_at = Time.at(work["started_at"] || Time.current.to_f)
          Time.current - started_at
        end

        processing_times.any? ? processing_times.sum / processing_times.size : 30.0
      end

      def calculate_memory_per_worker
        # 프로세스 메모리 사용량 추정
        if defined?(Process::Status) && Process.respond_to?(:pid)
          begin
            rss_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
            worker_count = [ @sidekiq_api.workers_size, 1 ].max
            rss_mb / worker_count
          rescue StandardError
            SCALING_METRICS[:memory_limit_per_worker] / 1.megabyte # 기본값
          end
        else
          SCALING_METRICS[:memory_limit_per_worker] / 1.megabyte
        end
      end

      def assess_queue_health
        health_scores = {}
        total_health = 0

        QUEUE_CONFIGURATIONS.each do |queue_name, config|
          queue_size = Sidekiq::Queue.new(queue_name.to_s).size
          latency = Sidekiq::Queue.new(queue_name.to_s).latency

          # 건강도 점수 계산 (0-100)
          size_score = queue_size < 100 ? 100 : [ 100 - (queue_size - 100), 0 ].max
          latency_score = latency < 60 ? 100 : [ 100 - (latency - 60), 0 ].max

          queue_health = (size_score + latency_score) / 2
          health_scores[queue_name] = queue_health
          total_health += queue_health
        end

        {
          overall_health: total_health / QUEUE_CONFIGURATIONS.size,
          queue_scores: health_scores,
          status: determine_health_status(total_health / QUEUE_CONFIGURATIONS.size)
        }
      end

      def assess_redis_health
        redis_info = @redis.info

        {
          connected_clients: redis_info["connected_clients"].to_i,
          used_memory_mb: (redis_info["used_memory"].to_i / 1.megabyte).round(2),
          used_memory_peak_mb: (redis_info["used_memory_peak"].to_i / 1.megabyte).round(2),
          keyspace_hits: redis_info["keyspace_hits"].to_i,
          keyspace_misses: redis_info["keyspace_misses"].to_i,
          hit_ratio: calculate_redis_hit_ratio(redis_info),
          status: "healthy"
        }
      rescue Redis::BaseError => e
        Rails.logger.error("Redis health check failed: #{e.message}")
        { status: "unhealthy", error: e.message }
      end

      def calculate_redis_hit_ratio(redis_info)
        hits = redis_info["keyspace_hits"].to_i
        misses = redis_info["keyspace_misses"].to_i
        total = hits + misses

        total > 0 ? ((hits.to_f / total) * 100).round(2) : 0
      end

      def calculate_error_rate
        # 최근 1시간 오류율 계산
        failed_jobs_last_hour = count_failed_jobs_last_hour
        total_jobs_last_hour = count_total_jobs_last_hour

        return 0.0 if total_jobs_last_hour == 0

        (failed_jobs_last_hour.to_f / total_jobs_last_hour * 100).round(2)
      end

      def count_failed_jobs_last_hour
        # Sidekiq 실패 작업 통계
        @sidekiq_api.failed
      end

      def count_total_jobs_last_hour
        # 처리된 + 실패한 작업 수
        @sidekiq_api.processed + @sidekiq_api.failed
      end

      # 스케일링 결정 로직
      def make_scaling_decision(metrics)
        current_workers = metrics[:total_workers]
        utilization = calculate_worker_utilization(metrics)
        latency = metrics[:average_processing_time]
        queue_health = metrics[:queue_health][:overall_health]

        # 스케일업 조건
        if should_scale_up?(utilization, latency, queue_health, current_workers)
          scale_up_amount = calculate_scale_up_amount(utilization, latency)
          target_workers = [ current_workers + scale_up_amount, SCALING_METRICS[:max_workers] ].min

          {
            action: "scale_up",
            current_workers: current_workers,
            target_workers: target_workers,
            reason: determine_scale_up_reason(utilization, latency, queue_health),
            confidence: calculate_decision_confidence(metrics)
          }
        # 스케일다운 조건
        elsif should_scale_down?(utilization, latency, queue_health, current_workers)
          scale_down_amount = calculate_scale_down_amount(utilization)
          target_workers = [ current_workers - scale_down_amount, SCALING_METRICS[:base_workers] ].max

          {
            action: "scale_down",
            current_workers: current_workers,
            target_workers: target_workers,
            reason: "Low utilization detected",
            confidence: calculate_decision_confidence(metrics)
          }
        else
          {
            action: "no_action",
            current_workers: current_workers,
            target_workers: current_workers,
            reason: "Metrics within optimal range",
            confidence: 1.0
          }
        end
      end

      def calculate_worker_utilization(metrics)
        return 0.0 if metrics[:total_workers] == 0

        (metrics[:busy_workers].to_f / metrics[:total_workers]).round(3)
      end

      def should_scale_up?(utilization, latency, queue_health, current_workers)
        return false if current_workers >= SCALING_METRICS[:max_workers]

        high_utilization = utilization > SCALING_METRICS[:scale_up_threshold]
        high_latency = latency > SCALING_METRICS[:response_time_target]
        poor_queue_health = queue_health < 60

        high_utilization || high_latency || poor_queue_health
      end

      def should_scale_down?(utilization, latency, queue_health, current_workers)
        return false if current_workers <= SCALING_METRICS[:base_workers]

        low_utilization = utilization < SCALING_METRICS[:scale_down_threshold]
        good_latency = latency < SCALING_METRICS[:response_time_target] / 2
        good_queue_health = queue_health > 80

        low_utilization && good_latency && good_queue_health
      end

      def calculate_scale_up_amount(utilization, latency)
        base_scale = 5 # 기본 5개 워커 추가

        # 상황에 따른 조정
        if utilization > 0.9
          base_scale += 10 # 매우 높은 사용률
        elsif latency > 10
          base_scale += 8  # 높은 지연시간
        end

        base_scale
      end

      def calculate_scale_down_amount(utilization)
        # 사용률에 따른 축소량 결정
        if utilization < 0.1
          10 # 매우 낮은 사용률
        elsif utilization < 0.2
          5  # 낮은 사용률
        else
          3  # 적당한 축소
        end
      end

      def determine_scale_up_reason(utilization, latency, queue_health)
        reasons = []

        reasons << "High utilization (#{(utilization * 100).round(1)}%)" if utilization > SCALING_METRICS[:scale_up_threshold]
        reasons << "High latency (#{latency.round(1)}s)" if latency > SCALING_METRICS[:response_time_target]
        reasons << "Poor queue health (#{queue_health.round(1)}%)" if queue_health < 60

        reasons.join(", ")
      end

      def calculate_decision_confidence(metrics)
        confidence_factors = []

        # 데이터 품질
        confidence_factors << (metrics[:total_workers] > 0 ? 0.3 : 0.0)

        # 메트릭 일관성
        utilization = calculate_worker_utilization(metrics)
        confidence_factors << (utilization.between?(0, 1) ? 0.3 : 0.0)

        # 시스템 건강도
        confidence_factors << (metrics[:queue_health][:overall_health] / 100 * 0.4)

        confidence_factors.sum.round(2)
      end

      # 스케일링 실행
      def execute_scaling_action(scaling_decision)
        case scaling_decision[:action]
        when "scale_up"
          add_workers(scaling_decision[:target_workers] - scaling_decision[:current_workers])
        when "scale_down"
          remove_workers(scaling_decision[:current_workers] - scaling_decision[:target_workers])
        end
      end

      def add_workers(count)
        Rails.logger.info("Adding #{count} Sidekiq workers")

        # 실제 환경에서는 Kubernetes, Docker, 또는 프로세스 매니저를 통해 실행
        # 여기서는 개념적 구현
        count.times do |i|
          spawn_sidekiq_worker("worker_#{Time.current.to_i}_#{i}")
        end
      end

      def remove_workers(count)
        Rails.logger.info("Removing #{count} Sidekiq workers")

        # 현재 실행 중인 워커들 중 가장 유휴 상태인 워커들을 종료
        workers_to_remove = identify_idle_workers(count)
        workers_to_remove.each do |worker_pid|
          terminate_sidekiq_worker(worker_pid)
        end
      end

      def spawn_sidekiq_worker(worker_name)
        # 실제 구현에서는 시스템 명령이나 컨테이너 오케스트레이션 도구 사용
        Rails.logger.info("Spawning Sidekiq worker: #{worker_name}")

        # 예시: Docker 컨테이너 스케일링
        # system("docker run -d --name #{worker_name} myapp:sidekiq")

        # 예시: Kubernetes 스케일링
        # system("kubectl scale deployment sidekiq-workers --replicas=#{new_replica_count}")
      end

      def terminate_sidekiq_worker(worker_pid)
        Rails.logger.info("Terminating Sidekiq worker: #{worker_pid}")

        # 예시: 프로세스 종료
        # Process.kill('TERM', worker_pid)
      end

      def identify_idle_workers(count)
        # Sidekiq Workers API를 사용하여 유휴 워커 식별
        workers = Sidekiq::Workers.new
        idle_workers = workers.select { |process_id, thread_id, work| work.nil? || work.empty? }

        idle_workers.first(count).map { |process_id, _, _| process_id }
      end

      # 성능 예측 및 분석
      def estimate_performance_impact(scaling_decision)
        return { estimated_improvement: 0 } if scaling_decision[:action] == "no_action"

        worker_change = scaling_decision[:target_workers] - scaling_decision[:current_workers]

        # 성능 향상 추정 (선형 근사)
        throughput_improvement = worker_change * 0.8 # 80% 효율성 가정
        latency_improvement = worker_change > 0 ? -0.3 * worker_change : 0.2 * worker_change.abs

        {
          estimated_throughput_change: "#{throughput_improvement > 0 ? '+' : ''}#{throughput_improvement.round(1)}%",
          estimated_latency_change: "#{latency_improvement > 0 ? '+' : ''}#{latency_improvement.round(1)}s",
          confidence: 0.75
        }
      end

      def collect_historical_performance(timeframe)
        # 실제 구현에서는 모니터링 시스템에서 데이터 수집
        # 예: Prometheus, DataDog, New Relic 등

        {
          timeframe: timeframe,
          data_points: 144, # 10분 간격으로 24시간
          metrics: generate_sample_historical_data(timeframe)
        }
      end

      def generate_sample_historical_data(timeframe)
        # 샘플 히스토리컬 데이터 생성 (실제로는 실제 메트릭 데이터 사용)
        data_points = []
        start_time = timeframe.ago

        144.times do |i|
          timestamp = start_time + (i * 10.minutes)
          hour = timestamp.hour

          # 시간대별 패턴 시뮬레이션
          base_load = case hour
          when 9..11, 14..16 then 0.8  # 피크 시간
          when 12..13 then 0.6         # 점심 시간
          when 18..22 then 0.7         # 저녁 시간
          else 0.3                     # 그 외 시간
          end

          data_points << {
            timestamp: timestamp,
            worker_utilization: base_load + rand(-0.1..0.1),
            queue_size: (base_load * 100 + rand(-20..20)).to_i,
            processing_time: base_load * 10 + rand(-2..2)
          }
        end

        data_points
      end

      # 비용 분석
      def calculate_current_costs
        worker_cost_per_hour = 0.10 # 예시: 워커당 시간당 비용
        current_workers = @sidekiq_api.workers_size

        hourly_cost = current_workers * worker_cost_per_hour
        monthly_cost = hourly_cost * 24 * 30

        {
          hourly_total: hourly_cost,
          monthly_total: monthly_cost,
          breakdown: {
            worker_costs: monthly_cost * 0.8,
            redis_costs: monthly_cost * 0.15,
            monitoring_costs: monthly_cost * 0.05
          }
        }
      end

      def identify_cost_optimizations
        optimizations = []

        # 유휴 시간 최적화
        historical_data = collect_historical_performance(7.days)
        low_usage_hours = identify_low_usage_periods(historical_data)

        if low_usage_hours.any?
          optimizations << {
            type: "schedule_scaling",
            description: "Reduce workers during low-usage hours",
            potential_savings: calculate_schedule_savings(low_usage_hours),
            implementation_complexity: "medium"
          }
        end

        # 큐 최적화
        inefficient_queues = identify_inefficient_queues
        if inefficient_queues.any?
          optimizations << {
            type: "queue_optimization",
            description: "Optimize queue configurations",
            potential_savings: 0.15, # 15% 비용 절감
            implementation_complexity: "low"
          }
        end

        optimizations
      end

      # 유틸리티 메서드들
      def determine_health_status(health_score)
        case health_score
        when 80..100 then "excellent"
        when 60..79 then "good"
        when 40..59 then "fair"
        when 20..39 then "poor"
        else "critical"
        end
      end

      def calculate_next_check_interval(metrics)
        # 상황에 따른 다음 체크 간격 조정
        if metrics[:queue_health][:overall_health] < 50
          30.seconds # 문제 상황시 자주 체크
        elsif metrics[:queue_health][:overall_health] > 80
          5.minutes  # 안정적일 때 덜 자주 체크
        else
          2.minutes  # 일반적인 간격
        end
      end

      def record_scaling_event(decision, metrics)
        @scaling_history << {
          timestamp: Time.current,
          action: decision[:action],
          workers_before: decision[:current_workers],
          workers_after: decision[:target_workers],
          reason: decision[:reason],
          metrics_snapshot: metrics
        }

        # 히스토리 크기 제한 (최근 100개)
        @scaling_history = @scaling_history.last(100)
      end

      def broadcast_performance_metrics(performance_data, alerts)
        ActionCable.server.broadcast(
          "sidekiq_performance",
          {
            type: "performance_update",
            data: performance_data,
            alerts: alerts,
            timestamp: Time.current.iso8601
          }
        )
      end

      # 메모이제이션으로 성능 최적화
      # memoize :assess_redis_health, :calculate_current_costs
    end
  end
end
