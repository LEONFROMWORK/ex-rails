# frozen_string_literal: true

module AiIntegration
  module Services
    # A/B 테스팅을 통해 AI 시스템의 다양한 파라미터를 실험하고 최적화
    class AbTestingService
      include Singleton

      # 실험 가능한 파라미터들
      TESTABLE_PARAMETERS = {
        quality_threshold: {
          type: :float,
          range: 0.5..0.9,
          default: 0.65,
          description: "AI 응답 품질 임계값"
        },
        complexity_threshold: {
          type: :integer,
          range: 20..80,
          default: 30,
          description: "쿼리 복잡도 티어 구분 임계값"
        },
        cache_similarity_threshold: {
          type: :float,
          range: 0.7..0.95,
          default: 0.85,
          description: "캐시 히트 유사도 임계값"
        },
        circuit_breaker_threshold: {
          type: :integer,
          range: 2..10,
          default: 5,
          description: "회로 차단기 실패 임계값"
        },
        retry_max_attempts: {
          type: :integer,
          range: 1..5,
          default: 3,
          description: "최대 재시도 횟수"
        },
        initial_tier_strategy: {
          type: :enum,
          values: [ :always_lowest, :complexity_based, :user_history_based, :time_based ],
          default: :complexity_based,
          description: "초기 모델 티어 선택 전략"
        }
      }.freeze

      def initialize
        @redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
        @monitoring = QualityMonitoringService.instance
        load_active_experiments
      end

      # 새로운 실험 생성
      def create_experiment(name:, parameter:, variants:, allocation: :random, traffic_percentage: 100)
        validate_parameter!(parameter)
        validate_variants!(parameter, variants)

        experiment = {
          id: SecureRandom.uuid,
          name: name,
          parameter: parameter,
          variants: variants,
          allocation: allocation,
          traffic_percentage: traffic_percentage,
          status: "active",
          created_at: Time.current,
          started_at: nil,
          ended_at: nil,
          metrics: initialize_metrics_tracking
        }

        save_experiment(experiment)

        Rails.logger.info("A/B test created: #{name} for #{parameter}")

        experiment
      end

      # 사용자에게 변형 할당
      def get_variant(user_id:, parameter:)
        # 활성 실험 찾기
        experiment = find_active_experiment(parameter)
        return get_default_value(parameter) unless experiment

        # 트래픽 비율 체크
        return get_default_value(parameter) unless in_experiment_traffic?(user_id, experiment)

        # 사용자별 변형 할당 (일관성 유지)
        variant_key = "#{experiment[:id]}:#{user_id}"
        cached_variant = @redis.get("ab_variant:#{variant_key}")

        if cached_variant
          variant = JSON.parse(cached_variant)
        else
          variant = allocate_variant(user_id, experiment)
          @redis.setex("ab_variant:#{variant_key}", 30.days, variant.to_json)

          # 할당 기록
          record_assignment(experiment, variant, user_id)
        end

        variant["value"]
      end

      # 실험 결과 기록
      def track_outcome(user_id:, parameter:, outcome:, metadata: {})
        experiment = find_active_experiment(parameter)
        return unless experiment

        variant_key = "#{experiment[:id]}:#{user_id}"
        variant_json = @redis.get("ab_variant:#{variant_key}")
        return unless variant_json

        variant = JSON.parse(variant_json)

        # 결과 기록
        outcome_data = {
          user_id: user_id,
          variant_id: variant["id"],
          variant_value: variant["value"],
          outcome: outcome,
          metadata: metadata,
          timestamp: Time.current
        }

        store_outcome(experiment, outcome_data)

        # 실시간 메트릭 업데이트
        update_experiment_metrics(experiment, variant, outcome)
      end

      # 실험 분석
      def analyze_experiment(experiment_id)
        experiment = load_experiment(experiment_id)
        return { error: "Experiment not found" } unless experiment

        analysis = {
          experiment: experiment.slice(:id, :name, :parameter, :status),
          duration_days: calculate_duration(experiment),
          total_assignments: count_assignments(experiment),
          variants: analyze_variants(experiment),
          statistical_significance: calculate_significance(experiment),
          recommendation: generate_recommendation(experiment)
        }

        # 상세 메트릭
        analysis[:detailed_metrics] = calculate_detailed_metrics(experiment)

        analysis
      end

      # 자동 실험 최적화
      def auto_optimize_experiments
        active_experiments = load_active_experiments

        active_experiments.each do |experiment|
          # 충분한 데이터가 모였는지 확인
          next unless sufficient_data?(experiment)

          # 통계적 유의성 확인
          significance = calculate_significance(experiment)
          next unless significance[:is_significant]

          # 승자 결정
          winner = determine_winner(experiment)

          if winner
            # 실험 종료 및 승자 적용
            conclude_experiment(experiment, winner)

            # 파라미터 업데이트
            update_system_parameter(experiment[:parameter], winner[:value])

            Rails.logger.info("Auto-optimized #{experiment[:parameter]} to #{winner[:value]}")
          end
        end
      end

      # 실험 리포트 생성
      def generate_report(experiment_id)
        analysis = analyze_experiment(experiment_id)

        report = {
          summary: generate_summary(analysis),
          visualizations: generate_visualizations(analysis),
          raw_data: export_raw_data(experiment_id),
          recommendations: analysis[:recommendation]
        }

        # PDF/HTML 리포트 생성 가능
        report
      end

      private

      def validate_parameter!(parameter)
        raise ArgumentError, "Unknown parameter: #{parameter}" unless TESTABLE_PARAMETERS.key?(parameter.to_sym)
      end

      def validate_variants!(parameter, variants)
        param_config = TESTABLE_PARAMETERS[parameter.to_sym]

        variants.each do |variant|
          case param_config[:type]
          when :float, :integer
            unless param_config[:range].include?(variant[:value])
              raise ArgumentError, "Variant value #{variant[:value]} outside valid range"
            end
          when :enum
            unless param_config[:values].include?(variant[:value].to_sym)
              raise ArgumentError, "Invalid enum value: #{variant[:value]}"
            end
          end
        end
      end

      def allocate_variant(user_id, experiment)
        case experiment[:allocation]
        when :random
          # 완전 무작위
          experiment[:variants].sample
        when :weighted
          # 가중치 기반
          weighted_random_variant(experiment[:variants])
        when :user_hash
          # 사용자 ID 해시 기반 (일관성)
          hash = Digest::MD5.hexdigest("#{experiment[:id]}:#{user_id}").to_i(16)
          index = hash % experiment[:variants].length
          experiment[:variants][index]
        when :sequential
          # 순차 할당
          count = @redis.incr("ab_assignment_count:#{experiment[:id]}")
          index = (count - 1) % experiment[:variants].length
          experiment[:variants][index]
        else
          experiment[:variants].first
        end
      end

      def in_experiment_traffic?(user_id, experiment)
        return true if experiment[:traffic_percentage] >= 100

        # 사용자 ID 기반 일관된 트래픽 분할
        hash = Digest::MD5.hexdigest("traffic:#{user_id}").to_i(16)
        (hash % 100) < experiment[:traffic_percentage]
      end

      def record_assignment(experiment, variant, user_id)
        @redis.hincrby("ab_assignments:#{experiment[:id]}", variant["id"], 1)

        # 시계열 데이터
        timestamp = Time.current.to_i
        @redis.zadd("ab_timeline:#{experiment[:id]}:#{variant['id']}", timestamp, user_id)
      end

      def update_experiment_metrics(experiment, variant, outcome)
        metric_key = "ab_metrics:#{experiment[:id]}:#{variant['id']}"

        # 성공/실패 카운트
        if outcome[:success]
          @redis.hincrby(metric_key, "success_count", 1)
        else
          @redis.hincrby(metric_key, "failure_count", 1)
        end

        # 품질 점수 누적
        if outcome[:quality_score]
          @redis.hincrbyfloat(metric_key, "quality_sum", outcome[:quality_score])
          @redis.hincrby(metric_key, "quality_count", 1)
        end

        # 응답 시간 누적
        if outcome[:response_time]
          @redis.hincrbyfloat(metric_key, "response_time_sum", outcome[:response_time])
          @redis.hincrby(metric_key, "response_time_count", 1)
        end

        # 비용 누적
        if outcome[:cost]
          @redis.hincrbyfloat(metric_key, "cost_sum", outcome[:cost])
        end
      end

      def calculate_significance(experiment)
        variants_data = experiment[:variants].map do |variant|
          metrics = get_variant_metrics(experiment[:id], variant["id"])

          {
            id: variant["id"],
            sample_size: metrics["success_count"].to_i + metrics["failure_count"].to_i,
            success_rate: calculate_success_rate(metrics),
            avg_quality: calculate_average_quality(metrics)
          }
        end

        # 최소 샘플 크기 확인
        min_sample_size = variants_data.map { |v| v[:sample_size] }.min
        return { is_significant: false, reason: "Insufficient data" } if min_sample_size < 100

        # 카이제곱 검정 또는 t-검정
        p_value = perform_statistical_test(variants_data)

        {
          is_significant: p_value < 0.05,
          p_value: p_value,
          confidence_level: (1 - p_value) * 100,
          sample_sizes: variants_data.map { |v| [ v[:id], v[:sample_size] ] }.to_h
        }
      end

      def perform_statistical_test(variants_data)
        # 간단한 비율 차이 검정 (실제로는 더 정교한 통계 필요)
        return 1.0 if variants_data.length < 2

        # 성공률 기준 z-검정
        control = variants_data.first
        treatment = variants_data.last

        p1 = control[:success_rate]
        p2 = treatment[:success_rate]
        n1 = control[:sample_size]
        n2 = treatment[:sample_size]

        return 1.0 if n1 == 0 || n2 == 0

        # 합동 비율
        p_pool = (p1 * n1 + p2 * n2) / (n1 + n2)

        # 표준 오차
        se = Math.sqrt(p_pool * (1 - p_pool) * (1.0/n1 + 1.0/n2))
        return 1.0 if se == 0

        # z-score
        z = (p2 - p1) / se

        # p-value (양측 검정)
        2 * (1 - normal_cdf(z.abs))
      end

      def normal_cdf(z)
        # 표준 정규 분포 누적 분포 함수 근사
        # 실제로는 통계 라이브러리 사용 권장
        0.5 * (1 + Math.erf(z / Math.sqrt(2)))
      end

      def determine_winner(experiment)
        variants_performance = experiment[:variants].map do |variant|
          metrics = get_variant_metrics(experiment[:id], variant["id"])

          score = calculate_variant_score(metrics)

          {
            id: variant["id"],
            value: variant["value"],
            score: score,
            metrics: metrics
          }
        end

        # 최고 성과 변형 선택
        variants_performance.max_by { |v| v[:score] }
      end

      def calculate_variant_score(metrics)
        # 복합 점수 계산 (성공률, 품질, 비용 고려)
        success_rate = calculate_success_rate(metrics)
        avg_quality = calculate_average_quality(metrics)
        avg_cost = calculate_average_cost(metrics)

        # 가중치 적용
        score = (success_rate * 0.3) + (avg_quality * 0.5) - (avg_cost * 0.2)

        score
      end

      def get_variant_metrics(experiment_id, variant_id)
        @redis.hgetall("ab_metrics:#{experiment_id}:#{variant_id}")
      end

      def calculate_success_rate(metrics)
        success = metrics["success_count"].to_f
        failure = metrics["failure_count"].to_f
        total = success + failure

        return 0 if total == 0

        success / total
      end

      def calculate_average_quality(metrics)
        sum = metrics["quality_sum"].to_f
        count = metrics["quality_count"].to_i

        return 0 if count == 0

        sum / count
      end

      def calculate_average_cost(metrics)
        sum = metrics["cost_sum"].to_f
        count = metrics["success_count"].to_i + metrics["failure_count"].to_i

        return 0 if count == 0

        sum / count
      end

      def sufficient_data?(experiment)
        min_assignments = experiment[:variants].map do |variant|
          count_variant_assignments(experiment[:id], variant["id"])
        end.min

        # 최소 100개 이상의 할당과 7일 이상 실행
        min_assignments >= 100 &&
        (Time.current - experiment[:started_at]) >= 7.days
      end

      def count_variant_assignments(experiment_id, variant_id)
        @redis.hget("ab_assignments:#{experiment_id}", variant_id).to_i
      end

      def generate_recommendation(experiment)
        analysis = analyze_variants(experiment)

        # 최고 성과 변형 찾기
        best_variant = analysis.max_by { |v| v[:performance_score] }

        # 개선 정도 계산
        baseline = analysis.find { |v| v[:is_control] } || analysis.first
        improvement = ((best_variant[:performance_score] - baseline[:performance_score]) / baseline[:performance_score] * 100).round(2)

        {
          recommended_value: best_variant[:value],
          expected_improvement: "#{improvement}%",
          confidence: calculate_recommendation_confidence(experiment),
          action: improvement > 5 ? "adopt" : "continue_testing"
        }
      end

      def save_experiment(experiment)
        @redis.hset("ab_experiments", experiment[:id], experiment.to_json)
        @redis.sadd("ab_experiments:active", experiment[:id])
      end

      def load_experiment(experiment_id)
        data = @redis.hget("ab_experiments", experiment_id)
        return nil unless data

        JSON.parse(data, symbolize_names: true)
      end

      def load_active_experiments
        experiment_ids = @redis.smembers("ab_experiments:active")

        experiment_ids.map { |id| load_experiment(id) }.compact
      end

      def get_default_value(parameter)
        TESTABLE_PARAMETERS[parameter.to_sym][:default]
      end
    end
  end
end
