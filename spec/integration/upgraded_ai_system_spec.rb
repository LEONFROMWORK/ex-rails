# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Upgraded AI System Integration', type: :integration do
  let(:user) { create(:user, :pro, credits: 1000) }
  let(:test_image) { File.binread(Rails.root.join('spec/fixtures/files/excel_screenshot.png')) }

  before do
    # Redis 초기화
    Redis.new.flushdb

    # 모니터링 서비스 초기화
    AiIntegration::Services::QualityMonitoringService.instance

    # WebMock 설정
    stub_openrouter_api
  end

  describe '멀티모달 이미지 분석 통합 테스트' do
    let(:coordinator) { AiIntegration::Services::MultimodalCoordinatorService.new(user: user) }

    it '간단한 쿼리는 cost_effective 티어를 사용한다' do
      result = coordinator.analyze_image(
        image_data: test_image,
        prompt: "What value is in cell A1?",
        options: { skip_cache: true }
      )

      expect(result[:success]).to be true
      expect(result[:tier_used]).to eq(:cost_effective)
      expect(result[:model_used]).to include('gemini-flash')
      expect(result[:processing_time]).to be < 3.0
    end

    it '복잡한 쿼리는 상위 티어를 사용한다' do
      result = coordinator.analyze_image(
        image_data: test_image,
        prompt: "Analyze the pivot table structure, identify all VLOOKUP errors, and suggest optimizations for the array formulas",
        options: { skip_cache: true }
      )

      expect(result[:tier_used]).to be_in([ :balanced, :premium ])
      expect(result[:confidence_score]).to be > 0.7
    end

    it '낮은 품질 응답 시 자동으로 상위 티어로 폴백한다' do
      # 첫 번째 응답은 낮은 품질
      stub_low_quality_response

      result = coordinator.analyze_image(
        image_data: test_image,
        prompt: "Explain this complex formula",
        options: { skip_cache: true }
      )

      expect(result[:is_fallback]).to be true
      expect(result[:fallback_details]).to be_present
      expect(result[:fallback_details][:attempts]).to be >= 2
      expect(result[:confidence_score]).to be >= 0.65
    end
  end

  describe '고급 캐싱 시스템' do
    let(:cache) { AiIntegration::Services::AdvancedCacheService.new }

    it '의미적으로 유사한 쿼리를 캐시에서 반환한다' do
      # 원본 응답 저장
      original_response = {
        analysis: "The SUM formula in cells A1:A10 calculates the total",
        confidence_score: 0.85,
        model_used: 'google/gemini-flash-1.5',
        tier_used: :cost_effective,
        success: true
      }

      cache.set_with_context(
        "How to use SUM formula in Excel",
        original_response,
        { user_id: user.id }
      )

      # 유사 쿼리로 조회
      similar_queries = [
        "How do I use SUM function in Excel",
        "Excel SUM formula usage",
        "Using the SUM formula in spreadsheets"
      ]

      similar_queries.each do |query|
        cached = cache.get_with_context(query, { user_id: user.id })

        expect(cached).not_to be_nil
        expect(cached['from_cache']).to be true
        expect(cached['cache_similarity']).to be >= 0.80
        expect(cached['analysis']).to include('SUM formula')
      end
    end

    it '프리페칭이 다음 단계를 미리 로드한다' do
      # Step 1 조회
      cache.get_with_context(
        "Excel tutorial step 1",
        { user_id: user.id }
      )

      # 백그라운드 프리페칭 대기
      sleep 1

      # Step 2, 3이 프리페치되었는지 확인
      prefetch_queue = cache.instance_variable_get(:@prefetch_queue)
      expect(prefetch_queue).not_to be_nil

      # 프리페치된 쿼리들 확인
      prefetched = []
      while !prefetch_queue.empty?
        prefetched << prefetch_queue.pop
      end

      expect(prefetched.map { |p| p[:query] }).to include(
        "Excel tutorial step 2",
        "Excel tutorial step 3"
      )
    end

    it '적응형 TTL이 품질과 접근 빈도에 따라 조정된다' do
      # 고품질, 자주 접근되는 응답
      high_quality_response = {
        analysis: "Detailed analysis",
        confidence_score: 0.95,
        cost_breakdown: { current_cost: 0.02 }
      }

      # 저품질, 드물게 접근되는 응답
      low_quality_response = {
        analysis: "Basic analysis",
        confidence_score: 0.65,
        cost_breakdown: { current_cost: 0.001 }
      }

      # TTL 계산 테스트
      ttl_high = cache.send(:calculate_adaptive_ttl, high_quality_response, {})
      ttl_low = cache.send(:calculate_adaptive_ttl, low_quality_response, {})

      expect(ttl_high).to be > ttl_low
      expect(ttl_high).to be <= 7.days
    end
  end

  describe 'A/B 테스팅 시스템' do
    let(:ab_service) { AiIntegration::Services::AbTestingService.instance }

    before do
      # 기존 실험 정리
      Redis.new.del('ab_experiments:active')
    end

    it '사용자별로 일관된 실험 변형을 할당한다' do
      experiment = ab_service.create_experiment(
        name: 'Quality Threshold Test',
        parameter: :quality_threshold,
        variants: [
          { id: 'control', value: 0.65, name: 'Current' },
          { id: 'test', value: 0.70, name: 'Higher' }
        ],
        allocation: :user_hash
      )

      # 같은 사용자는 항상 같은 변형
      values = []
      5.times do
        values << ab_service.get_variant(
          user_id: user.id,
          parameter: :quality_threshold
        )
      end

      expect(values.uniq.size).to eq(1)
      expect(values.first).to be_in([ 0.65, 0.70 ])
    end

    it '실험 결과를 추적하고 통계적 유의성을 계산한다' do
      experiment = ab_service.create_experiment(
        name: 'Cache Similarity Test',
        parameter: :cache_similarity_threshold,
        variants: [
          { id: 'control', value: 0.85 },
          { id: 'test', value: 0.80 }
        ]
      )

      # 시뮬레이션 데이터 생성
      100.times do |i|
        user_id = "test_user_#{i}"
        variant = ab_service.get_variant(
          user_id: user_id,
          parameter: :cache_similarity_threshold
        )

        # 변형에 따른 결과 시뮬레이션
        success = variant == 0.80 ? rand < 0.75 : rand < 0.65

        ab_service.track_outcome(
          user_id: user_id,
          parameter: :cache_similarity_threshold,
          outcome: {
            success: success,
            quality_score: success ? 0.8 + rand * 0.2 : 0.5 + rand * 0.3,
            response_time: 1.0 + rand * 2.0,
            cost: 0.01 + rand * 0.02
          }
        )
      end

      # 분석
      analysis = ab_service.analyze_experiment(experiment[:id])

      expect(analysis[:total_assignments]).to be >= 50
      expect(analysis[:variants]).to all(have_key(:success_rate))
      expect(analysis[:statistical_significance][:p_value]).to be_between(0, 1)
      expect(analysis[:recommendation]).to be_present
    end
  end

  describe '자동 튜닝 시스템' do
    let(:auto_tuning) { AiIntegration::Services::AutoTuningService.instance }

    it '시간대별로 최적화된 파라미터를 제공한다' do
      # 다양한 시간대 테스트
      time_params = {}

      [ 2, 9, 14, 20 ].each do |hour|
        Timecop.freeze(Time.current.change(hour: hour)) do
          time_params[hour] = auto_tuning.get_optimized_parameters(
            user_id: user.id,
            query_type: 'multimodal'
          )
        end
      end

      # 피크 시간(14시)과 새벽(2시)의 파라미터 차이 확인
      expect(time_params[14][:quality_threshold]).to be <= time_params[2][:quality_threshold]
      expect(time_params[14][:cache_ttl]).to be >= time_params[2][:cache_ttl]
    end

    it '이상 상황을 감지하고 자동으로 조정한다' do
      # 이상 상황 시뮬레이션
      allow_any_instance_of(AiIntegration::Services::QualityMonitoringService)
        .to receive(:get_realtime_stats).and_return({
          avg_quality: 0.45,  # 매우 낮은 품질
          error_rate: 0.25,   # 높은 오류율
          avg_response_time: 12.0  # 느린 응답
        })

      initial_params = auto_tuning.instance_variable_get(:@current_parameters).dup

      # 이상 감지 및 조정 실행
      auto_tuning.detect_and_adjust_anomalies

      adjusted_params = auto_tuning.instance_variable_get(:@current_parameters)

      # 조정 확인
      expect(adjusted_params[:quality_threshold]).to be < initial_params[:quality_threshold]
      expect(adjusted_params[:cache_ttl]).to be > initial_params[:cache_ttl]
      expect(adjusted_params[:retry_delays][:max_delay]).to be > initial_params[:retry_delays][:max_delay]
    end
  end

  describe '회로 차단기와 재시도 메커니즘' do
    let(:circuit_breaker) { AiIntegration::Services::CircuitBreakerService.new(failure_threshold: 3) }
    let(:retry_service) { AiIntegration::Services::RetryWithBackoffService.new(max_retries: 3) }

    it '연속 실패 시 회로가 열린다' do
      service_name = 'openrouter_test'

      # 3번 연속 실패
      3.times do
        expect {
          circuit_breaker.call(service_name) { raise 'API Error' }
        }.to raise_error(RuntimeError)
      end

      # 회로가 열림
      expect {
        circuit_breaker.call(service_name) { 'success' }
      }.to raise_error(AiIntegration::Services::CircuitBreakerService::CircuitOpenError)

      # 상태 확인
      status = circuit_breaker.status(service_name)
      expect(status[:state]).to eq(:open)
      expect(status[:failure_count]).to eq(3)
    end

    it '지수 백오프로 재시도 간격이 증가한다' do
      attempts = []

      begin
        retry_service.execute('test_api_call') do
          attempts << Time.current
          raise Net::ReadTimeout if attempts.size < 3
          'success'
        end
      rescue AiIntegration::Services::RetryWithBackoffService::RetryExhaustedError
        # 예상된 동작
      end

      expect(attempts.size).to eq(4) # 초기 시도 + 3번 재시도

      # 재시도 간격 확인
      intervals = []
      (1...attempts.size).each do |i|
        intervals << (attempts[i] - attempts[i-1])
      end

      # 간격이 증가하는지 확인 (지터 때문에 정확히 2배는 아님)
      expect(intervals[1]).to be > intervals[0]
      expect(intervals[2]).to be > intervals[1]
    end
  end

  describe '모니터링과 품질 추적' do
    let(:monitoring) { AiIntegration::Services::QualityMonitoringService.instance }

    it '실시간 메트릭을 수집하고 통계를 제공한다' do
      # 다양한 응답 시뮬레이션
      20.times do |i|
        response = {
          model: [ 'gemini-flash', 'claude-haiku', 'gpt-4v' ].sample,
          tier: [ :cost_effective, :balanced, :premium ].sample,
          confidence_score: 0.6 + rand * 0.4,
          processing_time: 0.5 + rand * 3.0,
          credits_used: 50 + rand(200),
          cost_breakdown: { current_cost: 0.001 + rand * 0.05 },
          success: rand > 0.1,
          is_fallback: rand > 0.8,
          quality_metrics: {
            confidence_score: 0.6 + rand * 0.4,
            quality_tier: [ 'poor', 'acceptable', 'good', 'excellent' ].sample
          }
        }

        monitoring.analyze_response(response)
      end

      # 통계 확인
      stats = monitoring.get_realtime_stats(window: 5.minutes)

      expect(stats[:avg_quality]).to be_between(0.6, 1.0)
      expect(stats[:total_requests]).to be >= 20
      expect(stats[:model_distribution]).to be_a(Hash)
      expect(stats[:quality_distribution]).to be_a(Hash)
    end

    it '품질 임계값 이하 시 알림을 발생시킨다' do
      # 알림 설정
      monitoring.configure_alerts({
        critical_quality_threshold: 0.5,
        warning_quality_threshold: 0.65
      })

      # 낮은 품질 응답
      low_quality_response = {
        model: 'test_model',
        tier: :cost_effective,
        confidence_score: 0.45,
        processing_time: 2.0,
        credits_used: 100,
        cost_breakdown: { current_cost: 0.01 },
        success: true,
        quality_metrics: {
          confidence_score: 0.45,
          quality_tier: 'poor'
        }
      }

      expect(Rails.logger).to receive(:error).with(/CRITICAL ALERT/)

      monitoring.analyze_response(low_quality_response)
    end
  end

  describe '전체 시스템 통합 플로우' do
    it '복잡한 이미지 분석 요청을 처리한다' do
      coordinator = AiIntegration::Services::MultimodalCoordinatorService.new(user: user)

      # 실제 분석 요청
      result = coordinator.analyze_excel_screenshot(
        image_data: test_image,
        context: {
          specific_question: "분석해주세요",
          error_context: "#REF! 오류가 발생했습니다"
        }
      )

      # 기본 검증
      expect(result[:success]).to be true
      expect(result[:analysis]).to be_present
      expect(result[:confidence_score]).to be > 0.6

      # 메타데이터 검증
      expect(result[:model_used]).to be_present
      expect(result[:tier_used]).to be_in([ :cost_effective, :balanced, :premium ])
      expect(result[:processing_time]).to be < 10.0

      # 비용 정보
      expect(result[:cost_info]).to be_present
      expect(result[:cost_info][:credits_used]).to be > 0

      # 품질 메트릭
      expect(result[:quality_metrics]).to be_present
      expect(result[:quality_metrics][:excel_relevance]).to be >= 0
    end

    it '캐시, A/B 테스트, 자동 튜닝이 모두 작동한다' do
      coordinator = AiIntegration::Services::MultimodalCoordinatorService.new(user: user)

      # 첫 번째 요청
      result1 = coordinator.analyze_image(
        image_data: test_image,
        prompt: "Excel 수식 분석",
        options: { conversation_id: 'test_conv_123' }
      )

      expect(result1[:success]).to be true
      expect(result1[:cache_hit]).to be_falsey

      # 두 번째 동일 요청 (캐시 히트 예상)
      result2 = coordinator.analyze_image(
        image_data: test_image,
        prompt: "Excel 수식 분석",
        options: { conversation_id: 'test_conv_123' }
      )

      expect(result2[:cache_hit]).to be true
      expect(result2[:processing_time]).to be < result1[:processing_time]

      # A/B 테스트 추적 확인
      redis = Redis.new
      ab_keys = redis.keys('ab_*')
      expect(ab_keys).not_to be_empty

      # 모니터링 데이터 확인
      monitoring_keys = redis.keys('ai_metrics:*')
      expect(monitoring_keys).not_to be_empty
    end
  end

  private

  def stub_openrouter_api
    # 성공 응답
    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .to_return(
        status: 200,
        body: {
          choices: [ {
            message: {
              content: "이미지를 분석했습니다. A1 셀에는 'Total'이라는 텍스트가 보입니다."
            },
            finish_reason: 'stop'
          } ],
          usage: {
            total_tokens: 150,
            prompt_tokens: 100,
            completion_tokens: 50
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # 임베딩 API
    stub_request(:post, "https://openrouter.ai/api/v1/embeddings")
      .to_return(
        status: 200,
        body: {
          data: [ {
            embedding: Array.new(1536) { rand }
          } ]
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def stub_low_quality_response
    call_count = 0

    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .to_return do |request|
        call_count += 1

        if call_count == 1
          # 첫 번째 응답: 낮은 품질
          {
            status: 200,
            body: {
              choices: [ {
                message: { content: "잘 모르겠습니다." },
                finish_reason: 'stop'
              } ],
              usage: { total_tokens: 50 }
            }.to_json
          }
        else
          # 두 번째 응답: 높은 품질
          {
            status: 200,
            body: {
              choices: [ {
                message: {
                  content: "복잡한 수식을 분석했습니다. SUMIFS 함수가 여러 조건을 확인하고 있습니다."
                },
                finish_reason: 'stop'
              } ],
              usage: { total_tokens: 200 }
            }.to_json
          }
        end
      end
  end
end
