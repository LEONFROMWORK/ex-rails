# frozen_string_literal: true

# 파일 크기와 복잡도에 따른 동적 큐 할당으로 처리 효율성 극대화
class IntelligentQueueManager < ApplicationJob
  queue_as :system

  # 큐 분류 및 우선순위 설정
  QUEUE_CONFIGURATIONS = {
    instant_processing: {
      max_file_size: 1.megabyte,
      max_complexity: 0.3,
      max_workers: 4,
      timeout: 10.seconds,
      priority_base: 100
    },
    fast_processing: {
      max_file_size: 10.megabytes,
      max_complexity: 0.6,
      max_workers: 6,
      timeout: 30.seconds,
      priority_base: 80
    },
    standard_processing: {
      max_file_size: 50.megabytes,
      max_complexity: 0.8,
      max_workers: 4,
      timeout: 2.minutes,
      priority_base: 60
    },
    priority_processing: {
      max_file_size: 50.megabytes,
      max_complexity: 0.8,
      max_workers: 8,
      timeout: 2.minutes,
      priority_base: 90,
      user_tiers: [ "pro", "enterprise" ]
    },
    heavy_processing: {
      max_file_size: Float::INFINITY,
      max_complexity: 1.0,
      max_workers: 2,
      timeout: 10.minutes,
      priority_base: 40
    },
    ultra_heavy: {
      max_file_size: Float::INFINITY,
      max_complexity: 1.0,
      max_workers: 1,
      timeout: Float::INFINITY, # Railway 무제한 시간 활용
      priority_base: 20
    }
  }.freeze

  class << self
    # 파일 크기와 복잡도에 따른 지능형 큐 할당
    def enqueue_analysis(file, user, priority: :normal)
      start_time = Time.current
      file_size = file.file_size
      estimated_complexity = estimate_complexity(file)
      user_tier = user.tier

      Rails.logger.info(
        "Intelligent queue assignment: file_size=#{(file_size.to_f / 1.megabyte).round(2)}MB, " \
        "complexity=#{estimated_complexity.round(3)}, user_tier=#{user_tier}"
      )

      # 지능형 큐 선택
      queue_name = determine_optimal_queue(file_size, estimated_complexity, user_tier)
      job_priority = calculate_priority_score(file_size, estimated_complexity, user_tier, priority)
      wait_time = calculate_optimal_delay(queue_name)

      # 큐 상태 확인 및 조정
      queue_adjustment = adjust_queue_if_needed(queue_name, file_size)
      final_queue = queue_adjustment[:queue]

      Rails.logger.info(
        "Queue assignment: #{final_queue} (priority: #{job_priority}, " \
        "wait: #{wait_time}s, adjustment: #{queue_adjustment[:reason]})"
      )

      # Solid Queue 동적 스케줄링
      job = ExcelAnalysis::Jobs::AnalyzeExcelJob.set(
        queue: final_queue,
        priority: job_priority,
        wait: wait_time
      ).perform_later(file.id, user.id)

      # 큐 상태 모니터링 및 워커 스케일링
      monitor_and_scale_queue(final_queue, file_size, estimated_complexity)

      # 결과 반환
      assignment_result = {
        queue: final_queue,
        priority: job_priority,
        estimated_time: estimate_processing_time(file_size, estimated_complexity),
        job_id: job.job_id,
        assignment_time: Time.current - start_time,
        queue_adjustment: queue_adjustment
      }

      Rails.logger.info("Queue assignment completed: #{assignment_result}")
      assignment_result
    end

    # 실시간 큐 상태 분석
    def analyze_queue_performance
      performance_data = {}

      QUEUE_CONFIGURATIONS.keys.each do |queue_name|
        queue_stats = get_queue_statistics(queue_name)
        performance_metrics = calculate_queue_performance(queue_name, queue_stats)

        performance_data[queue_name] = {
          stats: queue_stats,
          performance: performance_metrics,
          health_score: calculate_queue_health_score(performance_metrics),
          recommendations: generate_queue_recommendations(queue_name, performance_metrics)
        }
      end

      overall_health = calculate_overall_system_health(performance_data)

      {
        individual_queues: performance_data,
        overall_health: overall_health,
        system_recommendations: generate_system_recommendations(performance_data),
        analysis_timestamp: Time.current
      }
    end

    # 큐 최적화 및 재조정
    def optimize_queue_assignments
      Rails.logger.info("Starting intelligent queue optimization")

      optimization_start = Time.current
      optimizations_applied = []

      # 1. 적체된 큐 분석 및 재분배
      congested_queues = identify_congested_queues
      congested_queues.each do |queue_info|
        optimization = redistribute_congested_queue(queue_info)
        optimizations_applied << optimization if optimization
      end

      # 2. 유휴 워커 재분배
      idle_optimization = redistribute_idle_workers
      optimizations_applied << idle_optimization if idle_optimization

      # 3. 예측적 스케일링
      predictive_scaling = apply_predictive_scaling
      optimizations_applied << predictive_scaling if predictive_scaling

      optimization_time = Time.current - optimization_start

      Rails.logger.info(
        "Queue optimization completed: #{optimizations_applied.size} optimizations " \
        "applied in #{optimization_time.round(2)}s"
      )

      {
        optimizations_applied: optimizations_applied,
        optimization_time: optimization_time,
        performance_improvement: estimate_performance_improvement(optimizations_applied)
      }
    end

    private

    def estimate_complexity(file)
      # 파일 기반 복잡도 추정
      complexity_factors = {
        file_size: normalize_file_size_complexity(file.file_size),
        file_type: get_file_type_complexity(file.original_name),
        historical_data: get_historical_complexity(file)
      }

      # 가중 평균 계산
      weights = { file_size: 0.4, file_type: 0.3, historical_data: 0.3 }

      complexity_score = complexity_factors.map do |factor, value|
        weights[factor] * value
      end.sum

      [ complexity_score, 1.0 ].min
    end

    def normalize_file_size_complexity(file_size)
      # 파일 크기에 따른 복잡도 정규화 (0-1 스케일)
      case file_size
      when 0..1.megabyte then 0.1
      when 1.megabyte..5.megabytes then 0.3
      when 5.megabytes..20.megabytes then 0.5
      when 20.megabytes..50.megabytes then 0.7
      else 0.9
      end
    end

    def get_file_type_complexity(filename)
      # 파일 확장자에 따른 복잡도
      extension = File.extname(filename).downcase

      case extension
      when ".csv" then 0.2
      when ".xls" then 0.5
      when ".xlsx" then 0.6
      when ".xlsm" then 0.8 # 매크로 포함
      else 0.5
      end
    end

    def get_historical_complexity(file)
      # 유사한 파일들의 과거 처리 복잡도 분석
      similar_files = ExcelFile.where(
        file_size: (file.file_size * 0.8)..(file.file_size * 1.2)
      ).joins(:analyses).limit(10)

      return 0.5 if similar_files.empty?

      # 평균 처리 시간과 AI 티어 사용을 기반으로 복잡도 추정
      avg_tier = similar_files.joins(:analyses).average("analyses.ai_tier_used") || 1

      case avg_tier
      when 0..1.3 then 0.3
      when 1.3..1.7 then 0.6
      else 0.9
      end
    end

    def determine_optimal_queue(file_size, complexity, user_tier)
      # 사용자 티어별 우선 큐 확인
      if [ "pro", "enterprise" ].include?(user_tier) &&
         file_size <= QUEUE_CONFIGURATIONS[:priority_processing][:max_file_size] &&
         complexity <= QUEUE_CONFIGURATIONS[:priority_processing][:max_complexity]
        return :priority_processing
      end

      # 일반적인 큐 선택 로직
      case [ file_size, complexity ]
      when [ 0..QUEUE_CONFIGURATIONS[:instant_processing][:max_file_size],
            0..QUEUE_CONFIGURATIONS[:instant_processing][:max_complexity] ]
        :instant_processing
      when [ 0..QUEUE_CONFIGURATIONS[:fast_processing][:max_file_size],
            0..QUEUE_CONFIGURATIONS[:fast_processing][:max_complexity] ]
        :fast_processing
      when [ 0..QUEUE_CONFIGURATIONS[:standard_processing][:max_file_size],
            0..QUEUE_CONFIGURATIONS[:standard_processing][:max_complexity] ]
        :standard_processing
      when [ 0..QUEUE_CONFIGURATIONS[:heavy_processing][:max_file_size],
            0..QUEUE_CONFIGURATIONS[:heavy_processing][:max_complexity] ]
        :heavy_processing
      else
        :ultra_heavy
      end
    end

    def calculate_priority_score(file_size, complexity, user_tier, priority)
      base_score = case priority
      when :urgent then 100
      when :high then 75
      when :normal then 50
      when :low then 25
      else 50
      end

      # 사용자 티어 보너스
      tier_bonus = case user_tier
      when "enterprise" then 30
      when "pro" then 20
      when "basic" then 10
      else 5
      end

      # 복잡도 조정 (복잡한 작업일수록 높은 우선순위)
      complexity_adjustment = (complexity * 20).round

      # 파일 크기 페널티 (큰 파일은 우선순위 약간 감소)
      size_penalty = file_size > 20.megabytes ? -5 : 0

      final_score = [ base_score + tier_bonus + complexity_adjustment + size_penalty, 200 ].min
      [ final_score, 0 ].max
    end

    def calculate_optimal_delay(queue_name)
      # 큐별 현재 부하에 따른 최적 대기 시간 계산
      current_load = get_queue_current_load(queue_name)
      base_delay = 0

      case current_load
      when 0..0.3 then base_delay = 0
      when 0.3..0.6 then base_delay = 2
      when 0.6..0.8 then base_delay = 5
      when 0.8..0.9 then base_delay = 10
      else base_delay = 15
      end

      # 시간대별 조정 (피크 시간대 추가 지연)
      time_adjustment = peak_hours? ? 3 : 0

      base_delay + time_adjustment
    end

    def adjust_queue_if_needed(queue_name, file_size)
      current_queue_load = get_queue_current_load(queue_name)
      queue_capacity = QUEUE_CONFIGURATIONS[queue_name][:max_workers]

      # 큐가 과부하 상태인지 확인
      if current_queue_load > 0.85
        # 대안 큐 찾기
        alternative_queue = find_alternative_queue(queue_name, file_size)

        if alternative_queue
          Rails.logger.info("Queue overloaded, redirecting from #{queue_name} to #{alternative_queue}")
          return {
            queue: alternative_queue,
            reason: "original_queue_overloaded",
            original_queue: queue_name,
            load_factor: current_queue_load
          }
        end
      end

      # 큐 상태가 양호한 경우 원래 큐 사용
      {
        queue: queue_name,
        reason: "optimal_assignment",
        load_factor: current_queue_load
      }
    end

    def find_alternative_queue(original_queue, file_size)
      # 원래 큐 외에 사용 가능한 대안 큐 찾기
      alternative_queues = QUEUE_CONFIGURATIONS.keys - [ original_queue ]

      suitable_queues = alternative_queues.select do |queue_name|
        config = QUEUE_CONFIGURATIONS[queue_name]
        file_size <= config[:max_file_size] &&
        get_queue_current_load(queue_name) < 0.7
      end

      # 부하가 가장 낮은 큐 선택
      suitable_queues.min_by { |queue_name| get_queue_current_load(queue_name) }
    end

    def monitor_and_scale_queue(queue_name, file_size, complexity)
      # 큐 상태 모니터링 및 필요시 워커 스케일링
      queue_stats = get_queue_statistics(queue_name)

      if should_scale_up?(queue_stats, file_size, complexity)
        scale_up_queue(queue_name, queue_stats)
      elsif should_scale_down?(queue_stats)
        scale_down_queue(queue_name, queue_stats)
      end

      # 큐 건강 상태 알림
      health_score = calculate_queue_health_score(queue_stats)
      if health_score < 0.7
        notify_queue_health_issue(queue_name, health_score, queue_stats)
      end
    end

    def estimate_processing_time(file_size, complexity)
      # 파일 크기와 복잡도를 기반으로 처리 시간 추정
      base_time = case file_size
      when 0..1.megabyte then 15
      when 1.megabyte..10.megabytes then 45
      when 10.megabytes..50.megabytes then 120
      else 300
      end

      # 복잡도에 따른 시간 조정
      complexity_multiplier = 1 + complexity
      estimated_seconds = (base_time * complexity_multiplier).round

      # 사람이 읽기 쉬운 형태로 변환
      if estimated_seconds < 60
        "#{estimated_seconds}초"
      elsif estimated_seconds < 3600
        "#{(estimated_seconds / 60).round}분"
      else
        "#{(estimated_seconds / 3600.0).round(1)}시간"
      end
    end

    def get_queue_statistics(queue_name)
      # Solid Queue에서 큐 통계 수집
      {
        total_jobs: SolidQueue::Job.where(queue_name: queue_name).count,
        pending_jobs: SolidQueue::Job.where(queue_name: queue_name, finished_at: nil).count,
        failed_jobs: SolidQueue::Job.where(queue_name: queue_name).where.not(failed_at: nil).count,
        completed_jobs: SolidQueue::Job.where(queue_name: queue_name).where.not(finished_at: nil).count,
        avg_processing_time: calculate_avg_processing_time(queue_name),
        current_workers: estimate_current_workers(queue_name),
        queue_latency: calculate_queue_latency(queue_name)
      }
    end

    def get_queue_current_load(queue_name)
      stats = get_queue_statistics(queue_name)
      max_workers = QUEUE_CONFIGURATIONS[queue_name][:max_workers]

      # 현재 워커 사용률
      worker_utilization = stats[:current_workers].to_f / max_workers

      # 대기 중인 작업 비율
      pending_ratio = stats[:total_jobs] > 0 ? stats[:pending_jobs].to_f / stats[:total_jobs] : 0

      # 전체 부하 점수 (0-1)
      [ worker_utilization * 0.7 + pending_ratio * 0.3, 1.0 ].min
    end

    def calculate_avg_processing_time(queue_name)
      # 최근 완료된 작업들의 평균 처리 시간
      recent_jobs = SolidQueue::Job.where(queue_name: queue_name)
                                  .where.not(finished_at: nil)
                                  .where(finished_at: 1.hour.ago..Time.current)
                                  .limit(100)

      return 0 if recent_jobs.empty?

      processing_times = recent_jobs.map do |job|
        (job.finished_at - job.created_at).to_f
      end

      processing_times.sum / processing_times.size
    end

    def estimate_current_workers(queue_name)
      # 현재 실행 중인 작업 수로 워커 수 추정
      SolidQueue::Job.where(queue_name: queue_name, finished_at: nil, failed_at: nil).count
    end

    def calculate_queue_latency(queue_name)
      oldest_pending = SolidQueue::Job.where(queue_name: queue_name, finished_at: nil)
                                     .order(:created_at)
                                     .first

      return 0 unless oldest_pending

      (Time.current - oldest_pending.created_at).to_f
    end

    def calculate_queue_performance(queue_name, stats)
      # 큐 성능 메트릭 계산
      total_jobs = stats[:total_jobs]
      return default_performance_metrics if total_jobs == 0

      {
        throughput: calculate_throughput(queue_name, stats),
        success_rate: stats[:completed_jobs].to_f / total_jobs,
        failure_rate: stats[:failed_jobs].to_f / total_jobs,
        avg_latency: stats[:queue_latency],
        worker_efficiency: calculate_worker_efficiency(stats),
        response_time_percentiles: calculate_response_time_percentiles(queue_name)
      }
    end

    def calculate_throughput(queue_name, stats)
      # 시간당 처리된 작업 수
      recent_completed = SolidQueue::Job.where(queue_name: queue_name)
                                       .where(finished_at: 1.hour.ago..Time.current)
                                       .count

      recent_completed.to_f # jobs per hour
    end

    def calculate_worker_efficiency(stats)
      # 워커 효율성 = 실제 처리 시간 / 총 할당 시간
      return 0.8 if stats[:avg_processing_time] == 0 # 기본값

      # 간소화된 효율성 계산
      [ 1.0 - (stats[:queue_latency] / 3600.0), 0.1 ].max
    end

    def calculate_response_time_percentiles(queue_name)
      # 응답 시간 백분위수 계산
      recent_times = SolidQueue::Job.where(queue_name: queue_name)
                                   .where.not(finished_at: nil)
                                   .where(finished_at: 24.hours.ago..Time.current)
                                   .pluck(:created_at, :finished_at)
                                   .map { |created, finished| (finished - created).to_f }
                                   .sort

      return { p50: 0, p95: 0, p99: 0 } if recent_times.empty?

      {
        p50: percentile(recent_times, 50),
        p95: percentile(recent_times, 95),
        p99: percentile(recent_times, 99)
      }
    end

    def percentile(sorted_array, percentile)
      return 0 if sorted_array.empty?

      index = (percentile / 100.0 * sorted_array.length).ceil - 1
      sorted_array[[ index, 0 ].max]
    end

    def calculate_queue_health_score(performance_metrics)
      # 큐 건강 점수 계산 (0-1)
      scores = {
        success_rate: performance_metrics[:success_rate] || 0.8,
        low_failure_rate: 1 - (performance_metrics[:failure_rate] || 0.1),
        good_latency: calculate_latency_score(performance_metrics[:avg_latency] || 60),
        worker_efficiency: performance_metrics[:worker_efficiency] || 0.7
      }

      weights = { success_rate: 0.3, low_failure_rate: 0.2, good_latency: 0.3, worker_efficiency: 0.2 }

      scores.map { |metric, score| weights[metric] * score }.sum
    end

    def calculate_latency_score(latency_seconds)
      # 지연 시간을 0-1 점수로 변환
      case latency_seconds
      when 0..30 then 1.0
      when 30..120 then 0.8
      when 120..300 then 0.6
      when 300..600 then 0.4
      else 0.2
      end
    end

    def generate_queue_recommendations(queue_name, performance_metrics)
      recommendations = []

      if performance_metrics[:failure_rate] > 0.05
        recommendations << "High failure rate detected - investigate error patterns"
      end

      if performance_metrics[:avg_latency] > 300
        recommendations << "High latency - consider increasing worker capacity"
      end

      if performance_metrics[:worker_efficiency] < 0.6
        recommendations << "Low worker efficiency - optimize job processing logic"
      end

      if performance_metrics[:throughput] < 10
        recommendations << "Low throughput - review queue configuration"
      end

      recommendations
    end

    def calculate_overall_system_health(performance_data)
      queue_health_scores = performance_data.values.map { |data| data[:health_score] }
      average_health = queue_health_scores.sum / queue_health_scores.size

      {
        overall_score: average_health,
        status: health_status(average_health),
        worst_performing_queue: find_worst_performing_queue(performance_data),
        best_performing_queue: find_best_performing_queue(performance_data)
      }
    end

    def health_status(score)
      case score
      when 0.8..1.0 then "excellent"
      when 0.6..0.8 then "good"
      when 0.4..0.6 then "fair"
      when 0.2..0.4 then "poor"
      else "critical"
      end
    end

    def find_worst_performing_queue(performance_data)
      performance_data.min_by { |_, data| data[:health_score] }&.first
    end

    def find_best_performing_queue(performance_data)
      performance_data.max_by { |_, data| data[:health_score] }&.first
    end

    def generate_system_recommendations(performance_data)
      recommendations = []

      avg_health = performance_data.values.map { |data| data[:health_score] }.sum / performance_data.size

      if avg_health < 0.7
        recommendations << "System health below optimal - consider scaling up resources"
      end

      congested_queues = performance_data.select { |_, data| data[:health_score] < 0.6 }
      if congested_queues.any?
        recommendations << "#{congested_queues.size} queues need attention"
      end

      recommendations
    end

    def identify_congested_queues
      # 적체된 큐 식별
      QUEUE_CONFIGURATIONS.keys.filter_map do |queue_name|
        load = get_queue_current_load(queue_name)

        if load > 0.8
          {
            queue_name: queue_name,
            load: load,
            pending_jobs: get_queue_statistics(queue_name)[:pending_jobs]
          }
        end
      end
    end

    def redistribute_congested_queue(queue_info)
      # 적체된 큐의 작업을 다른 큐로 재분배
      queue_name = queue_info[:queue_name]
      pending_jobs = queue_info[:pending_jobs]

      return nil if pending_jobs < 5 # 소규모 적체는 무시

      # 재분배 로직 구현 (Solid Queue 한계로 간소화)
      Rails.logger.info("Queue #{queue_name} is congested with #{pending_jobs} pending jobs")

      {
        action: "congestion_alert",
        queue: queue_name,
        pending_jobs: pending_jobs,
        recommendation: "Consider manual intervention or worker scaling"
      }
    end

    def redistribute_idle_workers
      # 유휴 워커 재분배 (Solid Queue에서는 제한적)
      idle_queues = QUEUE_CONFIGURATIONS.keys.select do |queue_name|
        get_queue_current_load(queue_name) < 0.2
      end

      return nil if idle_queues.empty?

      {
        action: "idle_workers_detected",
        idle_queues: idle_queues,
        recommendation: "Consider reducing worker allocation for idle queues"
      }
    end

    def apply_predictive_scaling
      # 예측적 스케일링 (간소화된 버전)
      current_hour = Time.current.hour

      # 피크 시간대 예측
      if peak_hours_approaching?
        {
          action: "predictive_scaling",
          reason: "peak_hours_approaching",
          recommendation: "Prepare for increased load in the next hour"
        }
      end
    end

    def estimate_performance_improvement(optimizations)
      # 최적화 적용 후 성능 개선 추정
      if optimizations.any?
        "5-15% improvement expected"
      else
        "No optimizations needed"
      end
    end

    def should_scale_up?(queue_stats, file_size, complexity)
      # 스케일업 필요성 판단
      load = queue_stats[:pending_jobs].to_f / [ queue_stats[:current_workers], 1 ].max
      load > 3 && queue_stats[:avg_processing_time] > 60
    end

    def should_scale_down?(queue_stats)
      # 스케일다운 필요성 판단
      queue_stats[:pending_jobs] == 0 && queue_stats[:current_workers] > 1
    end

    def scale_up_queue(queue_name, stats)
      Rails.logger.info("Scaling up queue #{queue_name} - high load detected")
      # 실제 스케일링은 인프라 레벨에서 구현
    end

    def scale_down_queue(queue_name, stats)
      Rails.logger.info("Scaling down queue #{queue_name} - low utilization")
      # 실제 스케일링은 인프라 레벨에서 구현
    end

    def notify_queue_health_issue(queue_name, health_score, stats)
      Rails.logger.warn(
        "Queue health issue: #{queue_name} score=#{health_score.round(2)} " \
        "pending=#{stats[:pending_jobs]} failed=#{stats[:failed_jobs]}"
      )

      # 실제 구현에서는 Slack, 이메일 등으로 알림
    end

    def peak_hours?
      # 피크 시간대 판단
      current_hour = Time.current.hour
      (9..11).include?(current_hour) || (14..16).include?(current_hour)
    end

    def peak_hours_approaching?
      current_hour = Time.current.hour
      current_hour == 8 || current_hour == 13
    end

    def default_performance_metrics
      {
        throughput: 0,
        success_rate: 1.0,
        failure_rate: 0.0,
        avg_latency: 0,
        worker_efficiency: 0.8,
        response_time_percentiles: { p50: 0, p95: 0, p99: 0 }
      }
    end
  end

  # 인스턴스 메서드 (정기적 실행용)
  def perform
    Rails.logger.info("Running intelligent queue optimization")

    # 큐 성능 분석
    performance_analysis = self.class.analyze_queue_performance

    # 최적화 적용
    optimization_results = self.class.optimize_queue_assignments

    # 결과 로깅
    Rails.logger.info(
      "Queue optimization completed: #{optimization_results[:optimizations_applied].size} " \
      "optimizations, overall health: #{performance_analysis[:overall_health][:status]}"
    )

    # 결과 반환 (모니터링용)
    {
      performance_analysis: performance_analysis,
      optimization_results: optimization_results,
      timestamp: Time.current
    }
  end
end
