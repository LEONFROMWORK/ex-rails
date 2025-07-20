# frozen_string_literal: true

class AiAutoTuningJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info("Starting AI auto-tuning cycle")

    # 자동 튜닝 실행
    auto_tuning = AiIntegration::Services::AutoTuningService.instance
    auto_tuning.run_tuning_cycle

    # A/B 테스트 자동 최적화
    ab_testing = AiIntegration::Services::AbTestingService.instance
    ab_testing.auto_optimize_experiments

    # 캐시 성능 분석 및 최적화
    analyze_and_optimize_cache

    # 다음 실행 스케줄링 (1시간 후)
    self.class.set(wait: 1.hour).perform_later

  rescue StandardError => e
    Rails.logger.error("AI auto-tuning failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # 실패시 30분 후 재시도
    self.class.set(wait: 30.minutes).perform_later
  end

  private

  def analyze_and_optimize_cache
    cache_service = AiIntegration::Services::AdvancedCacheService.new

    # 접근 패턴 분석
    patterns = cache_service.analyze_access_patterns

    # 인기 쿼리 프리페칭
    if patterns[:temporal][:peak_hour_approaching]
      cache_service.warm_cache(strategy: :popular)
    end

    # 예측된 쿼리 프리페칭
    if patterns[:sequences][:strong_patterns].any?
      cache_service.warm_cache(strategy: :predicted)
    end

    Rails.logger.info("Cache optimization completed: #{patterns[:prefetch_effectiveness]}")
  end
end
