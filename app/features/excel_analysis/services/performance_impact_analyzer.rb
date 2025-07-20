# frozen_string_literal: true

module ExcelAnalysis
  module Services
    # 성능 영향도 분석 시스템
    # 계산 집약적 수식 식별, 성능 병목 분석, 최적화 우선순위 제공
    class PerformanceImpactAnalyzer
      include ActiveModel::Model

      # 성능 분석 관련 오류
      class PerformanceAnalysisError < StandardError; end
      class BottleneckDetectionError < StandardError; end
      class OptimizationPriorityError < StandardError; end

      # 성능 등급
      PERFORMANCE_GRADES = {
        excellent: { score: 90..100, color: "#4CAF50", description: "우수한 성능" },
        good: { score: 70..89, color: "#8BC34A", description: "양호한 성능" },
        fair: { score: 50..69, color: "#FFC107", description: "보통 성능" },
        poor: { score: 30..49, color: "#FF9800", description: "개선 필요" },
        critical: { score: 0..29, color: "#F44336", description: "심각한 성능 문제" }
      }.freeze

      # 함수별 성능 특성
      FUNCTION_PERFORMANCE_PROFILES = {
        "SUMPRODUCT" => {
          base_cost: 10.0,
          scaling_factor: "O(n²)",
          memory_intensive: true,
          cpu_intensive: true,
          alternatives: [ "SUMIFS", "Array formulas" ],
          optimization_potential: 8.5
        },
        "VLOOKUP" => {
          base_cost: 5.0,
          scaling_factor: "O(n)",
          memory_intensive: false,
          cpu_intensive: true,
          alternatives: [ "XLOOKUP", "INDEX+MATCH" ],
          optimization_potential: 7.0
        },
        "INDIRECT" => {
          base_cost: 15.0,
          scaling_factor: "O(1)",
          memory_intensive: false,
          cpu_intensive: true,
          alternatives: [ "Direct references" ],
          optimization_potential: 9.0
        },
        "OFFSET" => {
          base_cost: 8.0,
          scaling_factor: "O(1)",
          memory_intensive: false,
          cpu_intensive: true,
          alternatives: [ "INDEX", "Direct references" ],
          optimization_potential: 6.0
        },
        "ARRAY_FORMULAS" => {
          base_cost: 20.0,
          scaling_factor: "O(n)",
          memory_intensive: true,
          cpu_intensive: true,
          alternatives: [ "SUMIFS", "COUNTIFS" ],
          optimization_potential: 8.0
        },
        "VOLATILE_FUNCTIONS" => {
          base_cost: 25.0,
          scaling_factor: "O(1)",
          memory_intensive: false,
          cpu_intensive: true,
          alternatives: [ "Non-volatile alternatives" ],
          optimization_potential: 9.5
        }
      }.freeze

      # 휘발성 함수 목록
      VOLATILE_FUNCTIONS = %w[
        NOW TODAY RAND RANDBETWEEN OFFSET INDIRECT
        CELL INFO
      ].freeze

      attr_reader :formula_engine_client, :dependency_graph_service

      def initialize
        @formula_engine_client = FormulaEngineClient.instance
        @dependency_graph_service = DependencyGraphService.new
      end

      # 전체 성능 영향도 분석
      # @param excel_file [ExcelFile] 분석할 Excel 파일
      # @param options [Hash] 분석 옵션
      # @return [Common::Result] 성능 분석 결과
      def analyze_performance_impact(excel_file, options = {})
        Rails.logger.info("성능 영향도 분석 시작: #{excel_file.id}")

        performance_analysis = {
          excel_file_id: excel_file.id,
          analysis_timestamp: Time.current,
          overall_performance: {},
          bottleneck_analysis: {},
          formula_performance: {},
          optimization_opportunities: [],
          performance_recommendations: [],
          risk_assessment: {},
          benchmarking_data: {}
        }

        begin
          # 1. 기본 수식 분석
          formula_analysis = perform_base_formula_analysis(excel_file)
          return formula_analysis if formula_analysis.failure?

          base_data = formula_analysis.value

          # 2. 성능 집약적 수식 식별
          intensive_formulas = identify_performance_intensive_formulas(base_data)
          performance_analysis[:formula_performance] = intensive_formulas

          # 3. 병목 지점 분석
          bottleneck_analysis = analyze_performance_bottlenecks(base_data, intensive_formulas)
          performance_analysis[:bottleneck_analysis] = bottleneck_analysis

          # 4. 전체 성능 점수 계산
          overall_performance = calculate_overall_performance_score(intensive_formulas, bottleneck_analysis)
          performance_analysis[:overall_performance] = overall_performance

          # 5. 최적화 기회 식별
          optimization_opportunities = identify_optimization_opportunities(intensive_formulas, base_data)
          performance_analysis[:optimization_opportunities] = optimization_opportunities

          # 6. 성능 권장사항 생성
          recommendations = generate_performance_recommendations(performance_analysis)
          performance_analysis[:performance_recommendations] = recommendations

          # 7. 위험도 평가
          risk_assessment = assess_performance_risks(performance_analysis)
          performance_analysis[:risk_assessment] = risk_assessment

          # 8. 벤치마킹 데이터 생성
          if options[:include_benchmarking]
            benchmarking_data = generate_benchmarking_data(performance_analysis)
            performance_analysis[:benchmarking_data] = benchmarking_data
          end

          # 9. 시뮬레이션 분석 (옵션)
          if options[:run_simulation]
            simulation_results = run_performance_simulation(excel_file, performance_analysis)
            performance_analysis[:simulation_results] = simulation_results
          end

          Common::Result.success(performance_analysis)

        rescue StandardError => e
          Rails.logger.error("성능 영향도 분석 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "성능 분석 실패: #{e.message}",
              code: "PERFORMANCE_ANALYSIS_ERROR",
              details: { excel_file_id: excel_file.id }
            )
          )
        end
      end

      # 실시간 성능 모니터링
      # @param excel_file [ExcelFile] 모니터링할 Excel 파일
      # @param monitoring_options [Hash] 모니터링 옵션
      # @return [Common::Result] 실시간 성능 데이터
      def monitor_realtime_performance(excel_file, monitoring_options = {})
        Rails.logger.info("실시간 성능 모니터링 시작: #{excel_file.id}")

        begin
          monitoring_data = {
            excel_file_id: excel_file.id,
            monitoring_started_at: Time.current,
            current_metrics: {},
            performance_alerts: [],
            trend_analysis: {},
            resource_usage: {}
          }

          # 현재 성능 메트릭 수집
          current_metrics = collect_current_performance_metrics(excel_file)
          monitoring_data[:current_metrics] = current_metrics

          # 성능 경고 확인
          performance_alerts = check_performance_alerts(current_metrics, monitoring_options)
          monitoring_data[:performance_alerts] = performance_alerts

          # 트렌드 분석 (이전 데이터와 비교)
          if monitoring_options[:include_trends]
            trend_analysis = analyze_performance_trends(excel_file, current_metrics)
            monitoring_data[:trend_analysis] = trend_analysis
          end

          # 리소스 사용량 분석
          resource_usage = analyze_resource_usage(current_metrics)
          monitoring_data[:resource_usage] = resource_usage

          Common::Result.success(monitoring_data)

        rescue StandardError => e
          Rails.logger.error("실시간 성능 모니터링 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "성능 모니터링 실패: #{e.message}",
              code: "PERFORMANCE_MONITORING_ERROR",
              details: { excel_file_id: excel_file.id }
            )
          )
        end
      end

      # 성능 최적화 시뮬레이션
      # @param excel_file [ExcelFile] Excel 파일
      # @param optimization_scenarios [Array] 최적화 시나리오들
      # @return [Common::Result] 시뮬레이션 결과
      def simulate_optimization_impact(excel_file, optimization_scenarios)
        Rails.logger.info("성능 최적화 시뮬레이션 시작: #{excel_file.id}")

        begin
          simulation_results = {
            excel_file_id: excel_file.id,
            scenarios: [],
            baseline_performance: {},
            comparison_matrix: {},
            roi_analysis: {},
            implementation_roadmap: {}
          }

          # 기준선 성능 측정
          baseline_analysis = analyze_performance_impact(excel_file)
          return baseline_analysis if baseline_analysis.failure?

          baseline_performance = baseline_analysis.value[:overall_performance]
          simulation_results[:baseline_performance] = baseline_performance

          # 각 최적화 시나리오 시뮬레이션
          optimization_scenarios.each_with_index do |scenario, index|
            scenario_result = simulate_optimization_scenario(
              excel_file,
              scenario,
              baseline_performance,
              index
            )

            if scenario_result.success?
              simulation_results[:scenarios] << scenario_result.value
            end
          end

          # 시나리오 비교 매트릭스 생성
          comparison_matrix = generate_scenario_comparison_matrix(simulation_results[:scenarios])
          simulation_results[:comparison_matrix] = comparison_matrix

          # ROI 분석
          roi_analysis = calculate_optimization_roi(simulation_results[:scenarios], baseline_performance)
          simulation_results[:roi_analysis] = roi_analysis

          # 구현 로드맵 생성
          implementation_roadmap = generate_implementation_roadmap(simulation_results[:scenarios])
          simulation_results[:implementation_roadmap] = implementation_roadmap

          Common::Result.success(simulation_results)

        rescue StandardError => e
          Rails.logger.error("성능 최적화 시뮬레이션 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "최적화 시뮬레이션 실패: #{e.message}",
              code: "OPTIMIZATION_SIMULATION_ERROR",
              details: { excel_file_id: excel_file.id }
            )
          )
        end
      end

      # 성능 보고서 생성
      # @param performance_analysis [Hash] 성능 분석 결과
      # @param report_options [Hash] 보고서 옵션
      # @return [Common::Result] 성능 보고서
      def generate_performance_report(performance_analysis, report_options = {})
        Rails.logger.info("성능 보고서 생성 시작")

        begin
          report = {
            title: "엑셀 성능 분석 보고서",
            generated_at: Time.current,
            executive_summary: {},
            detailed_analysis: {},
            charts_data: {},
            action_items: [],
            appendix: {}
          }

          # 경영진 요약
          executive_summary = generate_executive_summary(performance_analysis)
          report[:executive_summary] = executive_summary

          # 상세 분석
          detailed_analysis = generate_detailed_analysis(performance_analysis)
          report[:detailed_analysis] = detailed_analysis

          # 차트 데이터
          if report_options[:include_charts]
            charts_data = generate_charts_data(performance_analysis)
            report[:charts_data] = charts_data
          end

          # 액션 아이템
          action_items = generate_action_items(performance_analysis)
          report[:action_items] = action_items

          # 부록
          if report_options[:include_appendix]
            appendix = generate_report_appendix(performance_analysis)
            report[:appendix] = appendix
          end

          Common::Result.success(report)

        rescue StandardError => e
          Rails.logger.error("성능 보고서 생성 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "성능 보고서 생성 실패: #{e.message}",
              code: "PERFORMANCE_REPORT_ERROR"
            )
          )
        end
      end

      private

      # 기본 수식 분석 수행
      def perform_base_formula_analysis(excel_file)
        analysis_service = FormulaAnalysisService.new(excel_file)
        analysis_result = analysis_service.analyze
        return analysis_result if analysis_result.failure?

        Common::Result.success(analysis_result.value[:formula_analysis])
      end

      # 성능 집약적 수식 식별
      def identify_performance_intensive_formulas(base_data)
        intensive_formulas = {
          high_cost_formulas: [],
          volatile_formulas: [],
          array_formulas: [],
          complex_lookups: [],
          nested_functions: [],
          large_range_operations: []
        }

        formulas = base_data&.dig("formulas") || []

        formulas.each do |formula_info|
          formula = formula_info["formula"]
          cell = formula_info["cell"]

          # 성능 비용 계산
          performance_cost = calculate_formula_performance_cost(formula)

          if performance_cost > 50.0
            intensive_formulas[:high_cost_formulas] << {
              cell: cell,
              formula: formula,
              cost_score: performance_cost,
              primary_issue: identify_primary_performance_issue(formula)
            }
          end

          # 휘발성 함수 검사
          if contains_volatile_functions?(formula)
            intensive_formulas[:volatile_formulas] << {
              cell: cell,
              formula: formula,
              volatile_functions: extract_volatile_functions(formula),
              recalculation_impact: calculate_recalculation_impact(formula)
            }
          end

          # 배열 수식 검사
          if is_array_formula?(formula)
            intensive_formulas[:array_formulas] << {
              cell: cell,
              formula: formula,
              array_size: estimate_array_size(formula),
              optimization_potential: calculate_array_optimization_potential(formula)
            }
          end

          # 복잡한 조회 함수 검사
          if contains_complex_lookups?(formula)
            intensive_formulas[:complex_lookups] << {
              cell: cell,
              formula: formula,
              lookup_functions: extract_lookup_functions(formula),
              data_size_impact: estimate_lookup_data_impact(formula)
            }
          end

          # 중첩 함수 검사
          nesting_depth = calculate_nesting_depth(formula)
          if nesting_depth > 5
            intensive_formulas[:nested_functions] << {
              cell: cell,
              formula: formula,
              nesting_depth: nesting_depth,
              simplification_potential: calculate_simplification_potential(formula)
            }
          end

          # 큰 범위 연산 검사
          if contains_large_range_operations?(formula)
            intensive_formulas[:large_range_operations] << {
              cell: cell,
              formula: formula,
              range_sizes: extract_range_sizes(formula),
              memory_impact: calculate_range_memory_impact(formula)
            }
          end
        end

        intensive_formulas
      end

      # 성능 병목 분석
      def analyze_performance_bottlenecks(base_data, intensive_formulas)
        bottlenecks = {
          critical_bottlenecks: [],
          dependency_bottlenecks: [],
          calculation_chains: [],
          resource_bottlenecks: [],
          architectural_issues: []
        }

        # 중요 병목 지점 식별
        all_intensive = [
          intensive_formulas[:high_cost_formulas],
          intensive_formulas[:volatile_formulas],
          intensive_formulas[:array_formulas]
        ].flatten

        critical_threshold = 80.0
        all_intensive.each do |formula_info|
          cost = formula_info[:cost_score] || formula_info[:recalculation_impact] || 0

          if cost > critical_threshold
            bottlenecks[:critical_bottlenecks] << {
              cell: formula_info[:cell],
              formula: formula_info[:formula],
              bottleneck_type: classify_bottleneck_type(formula_info),
              severity: calculate_bottleneck_severity(cost),
              impact_radius: calculate_impact_radius(formula_info[:cell], base_data)
            }
          end
        end

        # 의존성 병목 분석
        dependency_bottlenecks = analyze_dependency_bottlenecks(base_data)
        bottlenecks[:dependency_bottlenecks] = dependency_bottlenecks

        # 계산 체인 분석
        calculation_chains = analyze_calculation_chains(base_data, intensive_formulas)
        bottlenecks[:calculation_chains] = calculation_chains

        # 리소스 병목 분석
        resource_bottlenecks = analyze_resource_bottlenecks(intensive_formulas)
        bottlenecks[:resource_bottlenecks] = resource_bottlenecks

        # 아키텍처 이슈 분석
        architectural_issues = analyze_architectural_issues(base_data, intensive_formulas)
        bottlenecks[:architectural_issues] = architectural_issues

        bottlenecks
      end

      # 전체 성능 점수 계산
      def calculate_overall_performance_score(intensive_formulas, bottleneck_analysis)
        base_score = 100.0

        # 고비용 수식 패널티
        high_cost_penalty = intensive_formulas[:high_cost_formulas].length * 5.0
        base_score -= high_cost_penalty

        # 휘발성 함수 패널티
        volatile_penalty = intensive_formulas[:volatile_formulas].length * 8.0
        base_score -= volatile_penalty

        # 배열 수식 패널티
        array_penalty = intensive_formulas[:array_formulas].length * 6.0
        base_score -= array_penalty

        # 중요 병목 패널티
        critical_bottleneck_penalty = bottleneck_analysis[:critical_bottlenecks].length * 15.0
        base_score -= critical_bottleneck_penalty

        # 최종 점수 정규화
        final_score = [ base_score, 0.0 ].max

        {
          overall_score: final_score.round(1),
          grade: determine_performance_grade(final_score),
          score_breakdown: {
            base_score: 100.0,
            high_cost_penalty: high_cost_penalty,
            volatile_penalty: volatile_penalty,
            array_penalty: array_penalty,
            critical_bottleneck_penalty: critical_bottleneck_penalty
          },
          performance_factors: analyze_performance_factors(intensive_formulas, bottleneck_analysis)
        }
      end

      # 최적화 기회 식별
      def identify_optimization_opportunities(intensive_formulas, base_data)
        opportunities = []

        # VLOOKUP → XLOOKUP 최적화
        vlookup_opportunities = identify_vlookup_optimization_opportunities(intensive_formulas)
        opportunities.concat(vlookup_opportunities)

        # 휘발성 함수 최적화
        volatile_opportunities = identify_volatile_function_optimizations(intensive_formulas)
        opportunities.concat(volatile_opportunities)

        # 배열 수식 최적화
        array_opportunities = identify_array_formula_optimizations(intensive_formulas)
        opportunities.concat(array_opportunities)

        # 범위 최적화
        range_opportunities = identify_range_optimization_opportunities(intensive_formulas)
        opportunities.concat(range_opportunities)

        # 캐싱 기회
        caching_opportunities = identify_caching_opportunities(base_data, intensive_formulas)
        opportunities.concat(caching_opportunities)

        # 우선순위 정렬
        opportunities.sort_by { |opp| -opp[:impact_score] }
      end

      # 성능 권장사항 생성
      def generate_performance_recommendations(performance_analysis)
        recommendations = []

        overall_score = performance_analysis[:overall_performance][:overall_score]

        # 전체 성능 기반 권장사항
        if overall_score < 30
          recommendations << {
            type: "critical_performance_issue",
            priority: "critical",
            title: "심각한 성능 문제 해결 필요",
            description: "전체 성능 점수가 매우 낮습니다. 즉시 최적화가 필요합니다.",
            actions: [
              "가장 비용이 높은 수식들을 우선적으로 최적화",
              "휘발성 함수 사용 최소화",
              "복잡한 배열 수식을 단순한 함수로 교체"
            ],
            estimated_impact: "high"
          }
        elsif overall_score < 50
          recommendations << {
            type: "performance_improvement",
            priority: "high",
            title: "성능 개선 권장",
            description: "성능 최적화를 통해 계산 속도를 크게 향상시킬 수 있습니다.",
            actions: [
              "병목 지점 해결",
              "중복 계산 제거",
              "효율적인 함수로 교체"
            ],
            estimated_impact: "medium"
          }
        end

        # 특정 이슈 기반 권장사항
        bottlenecks = performance_analysis[:bottleneck_analysis][:critical_bottlenecks]
        if bottlenecks.any?
          recommendations << {
            type: "bottleneck_resolution",
            priority: "high",
            title: "병목 지점 해결",
            description: "#{bottlenecks.length}개의 중요 병목 지점이 발견되었습니다.",
            actions: bottlenecks.map { |b| "#{b[:cell]} 셀의 #{b[:bottleneck_type]} 문제 해결" },
            estimated_impact: "high"
          }
        end

        # 최적화 기회 기반 권장사항
        high_impact_opportunities = performance_analysis[:optimization_opportunities].select do |opp|
          opp[:impact_score] > 70
        end

        if high_impact_opportunities.any?
          recommendations << {
            type: "optimization_opportunities",
            priority: "medium",
            title: "고영향 최적화 기회",
            description: "#{high_impact_opportunities.length}개의 고영향 최적화 기회가 있습니다.",
            actions: high_impact_opportunities.map { |opp| opp[:description] },
            estimated_impact: "medium"
          }
        end

        recommendations
      end

      # 성능 위험도 평가
      def assess_performance_risks(performance_analysis)
        risks = {
          overall_risk_level: "medium",
          risk_factors: [],
          mitigation_strategies: [],
          monitoring_recommendations: []
        }

        overall_score = performance_analysis[:overall_performance][:overall_score]

        # 전체 위험도 결정
        risks[:overall_risk_level] = case overall_score
        when 0..30 then "critical"
        when 31..50 then "high"
        when 51..70 then "medium"
        else "low"
        end

        # 위험 요소 식별
        bottlenecks = performance_analysis[:bottleneck_analysis][:critical_bottlenecks]
        if bottlenecks.any?
          risks[:risk_factors] << {
            type: "critical_bottlenecks",
            severity: "high",
            description: "중요 병목 지점으로 인한 성능 저하 위험",
            affected_areas: bottlenecks.map { |b| b[:cell] }
          }
        end

        volatile_formulas = performance_analysis[:formula_performance][:volatile_formulas]
        if volatile_formulas.length > 10
          risks[:risk_factors] << {
            type: "excessive_volatility",
            severity: "medium",
            description: "과도한 휘발성 함수로 인한 불필요한 재계산",
            affected_areas: volatile_formulas.map { |v| v[:cell] }
          }
        end

        # 완화 전략
        risks[:mitigation_strategies] = [
          "정기적인 성능 모니터링 실시",
          "최적화 우선순위에 따른 단계적 개선",
          "성능 테스트 자동화 도입",
          "팀 교육을 통한 성능 인식 제고"
        ]

        # 모니터링 권장사항
        risks[:monitoring_recommendations] = [
          "일일 성능 메트릭 확인",
          "병목 지점 실시간 알림 설정",
          "성능 기준선 정기 업데이트",
          "사용자 피드백 수집 체계 구축"
        ]

        risks
      end

      # 현재 성능 메트릭 수집
      def collect_current_performance_metrics(excel_file)
        {
          calculation_time: measure_calculation_time(excel_file),
          memory_usage: estimate_memory_usage(excel_file),
          formula_count: count_formulas(excel_file),
          volatile_function_count: count_volatile_functions(excel_file),
          dependency_depth: calculate_dependency_depth(excel_file),
          error_count: count_formula_errors(excel_file),
          last_updated: Time.current
        }
      end

      # 성능 경고 확인
      def check_performance_alerts(metrics, options)
        alerts = []

        # 계산 시간 경고
        if metrics[:calculation_time] > (options[:calculation_time_threshold] || 5000) # 5초
          alerts << {
            type: "slow_calculation",
            severity: "warning",
            message: "계산 시간이 임계값을 초과했습니다.",
            current_value: metrics[:calculation_time],
            threshold: options[:calculation_time_threshold] || 5000
          }
        end

        # 메모리 사용량 경고
        if metrics[:memory_usage] > (options[:memory_threshold] || 100_000_000) # 100MB
          alerts << {
            type: "high_memory_usage",
            severity: "warning",
            message: "메모리 사용량이 높습니다.",
            current_value: metrics[:memory_usage],
            threshold: options[:memory_threshold] || 100_000_000
          }
        end

        # 휘발성 함수 과다 사용 경고
        if metrics[:volatile_function_count] > (options[:volatile_function_threshold] || 20)
          alerts << {
            type: "excessive_volatile_functions",
            severity: "info",
            message: "휘발성 함수가 과도하게 사용되고 있습니다.",
            current_value: metrics[:volatile_function_count],
            threshold: options[:volatile_function_threshold] || 20
          }
        end

        alerts
      end

      # 헬퍼 메소드들

      def calculate_formula_performance_cost(formula)
        return 0.0 if formula.blank?

        cost = 0.0

        # 기본 복잡도
        cost += formula.length / 10.0

        # 함수별 비용 추가
        FUNCTION_PERFORMANCE_PROFILES.each do |func_pattern, profile|
          if formula.upcase.include?(func_pattern)
            cost += profile[:base_cost]
          end
        end

        # 중첩 깊이 비용
        nesting_depth = calculate_nesting_depth(formula)
        cost += nesting_depth * 5.0

        # 범위 참조 비용
        range_count = formula.scan(/[A-Z]+\d+:[A-Z]+\d+/).length
        cost += range_count * 10.0

        cost.round(2)
      end

      def identify_primary_performance_issue(formula)
        issues = []

        FUNCTION_PERFORMANCE_PROFILES.each do |func_pattern, profile|
          if formula.upcase.include?(func_pattern) && profile[:base_cost] > 10.0
            issues << func_pattern.downcase
          end
        end

        if calculate_nesting_depth(formula) > 5
          issues << "deep_nesting"
        end

        if formula.scan(/[A-Z]+\d+:[A-Z]+\d+/).length > 3
          issues << "multiple_ranges"
        end

        issues.first || "complexity"
      end

      def contains_volatile_functions?(formula)
        VOLATILE_FUNCTIONS.any? { |func| formula.upcase.include?(func) }
      end

      def extract_volatile_functions(formula)
        VOLATILE_FUNCTIONS.select { |func| formula.upcase.include?(func) }
      end

      def calculate_recalculation_impact(formula)
        volatile_functions = extract_volatile_functions(formula)
        base_impact = volatile_functions.length * 10.0

        # 수식 복잡도에 따른 가중치
        complexity_multiplier = 1 + (calculate_formula_performance_cost(formula) / 100.0)

        (base_impact * complexity_multiplier).round(2)
      end

      def is_array_formula?(formula)
        formula.include?("{") && formula.include?("}")
      end

      def estimate_array_size(formula)
        # 간단한 배열 크기 추정
        ranges = formula.scan(/[A-Z]+\d+:[A-Z]+\d+/)
        ranges.sum { |range| estimate_range_size(range) }
      end

      def calculate_array_optimization_potential(formula)
        array_size = estimate_array_size(formula)

        case array_size
        when 0..100 then 3.0
        when 101..1000 then 6.0
        when 1001..10000 then 8.0
        else 9.5
        end
      end

      def contains_complex_lookups?(formula)
        lookup_functions = %w[VLOOKUP HLOOKUP INDEX MATCH XLOOKUP]
        lookup_functions.any? { |func| formula.upcase.include?(func) }
      end

      def extract_lookup_functions(formula)
        lookup_functions = %w[VLOOKUP HLOOKUP INDEX MATCH XLOOKUP]
        lookup_functions.select { |func| formula.upcase.include?(func) }
      end

      def estimate_lookup_data_impact(formula)
        lookup_functions = extract_lookup_functions(formula)

        # VLOOKUP/HLOOKUP는 더 높은 영향도
        impact = 0.0
        impact += lookup_functions.count { |f| f.match?(/^[VH]LOOKUP$/) } * 5.0
        impact += lookup_functions.count { |f| f == "XLOOKUP" } * 2.0
        impact += lookup_functions.count { |f| f.match?(/^(INDEX|MATCH)$/) } * 3.0

        impact
      end

      def calculate_nesting_depth(formula)
        max_depth = 0
        current_depth = 0

        formula.each_char do |char|
          case char
          when "("
            current_depth += 1
            max_depth = [ max_depth, current_depth ].max
          when ")"
            current_depth -= 1
          end
        end

        max_depth
      end

      def calculate_simplification_potential(formula)
        nesting_depth = calculate_nesting_depth(formula)

        case nesting_depth
        when 0..3 then 2.0
        when 4..6 then 5.0
        when 7..9 then 7.5
        else 9.0
        end
      end

      def contains_large_range_operations?(formula)
        ranges = formula.scan(/[A-Z]+\d+:[A-Z]+\d+/)
        ranges.any? { |range| estimate_range_size(range) > 1000 }
      end

      def extract_range_sizes(formula)
        ranges = formula.scan(/[A-Z]+\d+:[A-Z]+\d+/)
        ranges.map { |range| estimate_range_size(range) }
      end

      def calculate_range_memory_impact(formula)
        total_cells = extract_range_sizes(formula).sum
        (total_cells / 1000.0 * 8.0).round(2) # 8KB per 1000 cells 추정
      end

      def estimate_range_size(range_ref)
        # 간단한 범위 크기 추정 (A1:C10 -> 30 cells)
        if range_ref.match(/([A-Z]+)(\d+):([A-Z]+)(\d+)/)
          start_col = $1
          start_row = $2.to_i
          end_col = $3
          end_row = $4.to_i

          col_diff = (end_col.bytes.sum - start_col.bytes.sum).abs + 1
          row_diff = (end_row - start_row).abs + 1

          col_diff * row_diff
        else
          1
        end
      end

      def classify_bottleneck_type(formula_info)
        if formula_info[:volatile_functions]
          "volatile_function"
        elsif formula_info[:array_size]
          "array_formula"
        elsif formula_info[:lookup_functions]
          "complex_lookup"
        elsif formula_info[:nesting_depth]
          "deep_nesting"
        else
          "high_complexity"
        end
      end

      def calculate_bottleneck_severity(cost_score)
        case cost_score
        when 0..50 then "low"
        when 51..80 then "medium"
        when 81..100 then "high"
        else "critical"
        end
      end

      def calculate_impact_radius(cell, base_data)
        # 해당 셀에 의존하는 다른 셀들의 수 계산
        5 # 예시 값
      end

      def analyze_dependency_bottlenecks(base_data)
        # 의존성 체인이 긴 경우나 순환 참조 등 분석
        []
      end

      def analyze_calculation_chains(base_data, intensive_formulas)
        # 계산 체인 분석
        []
      end

      def analyze_resource_bottlenecks(intensive_formulas)
        # CPU, 메모리 등 리소스 병목 분석
        {
          cpu_intensive_formulas: intensive_formulas[:high_cost_formulas].length,
          memory_intensive_formulas: intensive_formulas[:large_range_operations].length,
          io_intensive_operations: 0
        }
      end

      def analyze_architectural_issues(base_data, intensive_formulas)
        # 아키텍처 레벨 이슈 분석
        []
      end

      def determine_performance_grade(score)
        PERFORMANCE_GRADES.each do |grade, info|
          return grade if info[:score].include?(score)
        end
        :critical
      end

      def analyze_performance_factors(intensive_formulas, bottleneck_analysis)
        {
          formula_complexity: intensive_formulas[:high_cost_formulas].length,
          volatility_impact: intensive_formulas[:volatile_formulas].length,
          array_formula_impact: intensive_formulas[:array_formulas].length,
          bottleneck_severity: bottleneck_analysis[:critical_bottlenecks].length
        }
      end

      def identify_vlookup_optimization_opportunities(intensive_formulas)
        opportunities = []

        intensive_formulas[:complex_lookups].each do |lookup_info|
          if lookup_info[:lookup_functions].include?("VLOOKUP")
            opportunities << {
              type: "vlookup_to_xlookup",
              cell: lookup_info[:cell],
              description: "VLOOKUP을 XLOOKUP으로 교체하여 성능 향상",
              impact_score: 75.0,
              implementation_effort: "low",
              estimated_improvement: "30-50%"
            }
          end
        end

        opportunities
      end

      def identify_volatile_function_optimizations(intensive_formulas)
        opportunities = []

        intensive_formulas[:volatile_formulas].each do |volatile_info|
          opportunities << {
            type: "volatile_function_replacement",
            cell: volatile_info[:cell],
            description: "휘발성 함수 #{volatile_info[:volatile_functions].join(', ')} 최적화",
            impact_score: 80.0,
            implementation_effort: "medium",
            estimated_improvement: "40-60%"
          }
        end

        opportunities
      end

      def identify_array_formula_optimizations(intensive_formulas)
        opportunities = []

        intensive_formulas[:array_formulas].each do |array_info|
          opportunities << {
            type: "array_formula_simplification",
            cell: array_info[:cell],
            description: "배열 수식을 단순 함수로 교체",
            impact_score: array_info[:optimization_potential] * 8.0,
            implementation_effort: "high",
            estimated_improvement: "20-40%"
          }
        end

        opportunities
      end

      def identify_range_optimization_opportunities(intensive_formulas)
        opportunities = []

        intensive_formulas[:large_range_operations].each do |range_info|
          opportunities << {
            type: "range_size_reduction",
            cell: range_info[:cell],
            description: "큰 범위 참조를 최적화",
            impact_score: 60.0,
            implementation_effort: "medium",
            estimated_improvement: "15-30%"
          }
        end

        opportunities
      end

      def identify_caching_opportunities(base_data, intensive_formulas)
        opportunities = []

        # 중복 계산이 많은 경우 캐싱 기회 식별
        # 실제로는 더 복잡한 분석 필요

        opportunities
      end

      def simulate_optimization_scenario(excel_file, scenario, baseline_performance, index)
        # 시나리오별 성능 시뮬레이션
        simulated_performance = {
          scenario_id: index,
          scenario_name: scenario[:name],
          optimizations_applied: scenario[:optimizations],
          projected_performance: {},
          implementation_complexity: scenario[:complexity] || "medium",
          estimated_effort_hours: scenario[:effort_hours] || 8
        }

        # 성능 향상 시뮬레이션 (간단한 모델)
        improvement_factor = calculate_improvement_factor(scenario[:optimizations])
        new_score = [ baseline_performance[:overall_score] * improvement_factor, 100.0 ].min

        simulated_performance[:projected_performance] = {
          overall_score: new_score.round(1),
          grade: determine_performance_grade(new_score),
          improvement_percentage: ((new_score - baseline_performance[:overall_score]) / baseline_performance[:overall_score] * 100).round(1)
        }

        Common::Result.success(simulated_performance)
      end

      def calculate_improvement_factor(optimizations)
        base_factor = 1.0

        optimizations.each do |optimization|
          case optimization[:type]
          when "vlookup_to_xlookup" then base_factor += 0.15
          when "volatile_function_replacement" then base_factor += 0.25
          when "array_formula_simplification" then base_factor += 0.20
          when "range_size_reduction" then base_factor += 0.10
          end
        end

        [ base_factor, 2.0 ].min # 최대 100% 향상으로 제한
      end

      def generate_scenario_comparison_matrix(scenarios)
        # 시나리오 비교 매트릭스 생성
        matrix = {
          scenarios: scenarios.map { |s| s[:scenario_name] },
          metrics: [ "Performance Score", "Implementation Effort", "ROI" ],
          data: []
        }

        scenarios.each do |scenario|
          matrix[:data] << {
            scenario: scenario[:scenario_name],
            performance_score: scenario[:projected_performance][:overall_score],
            implementation_effort: scenario[:estimated_effort_hours],
            roi: calculate_scenario_roi(scenario)
          }
        end

        matrix
      end

      def calculate_optimization_roi(scenarios, baseline_performance)
        # ROI 계산
        roi_analysis = {
          baseline_score: baseline_performance[:overall_score],
          scenarios_roi: []
        }

        scenarios.each do |scenario|
          performance_gain = scenario[:projected_performance][:improvement_percentage]
          effort_cost = scenario[:estimated_effort_hours] * 100 # 시간당 $100 가정

          roi = (performance_gain / effort_cost * 1000).round(2) # ROI 정규화

          roi_analysis[:scenarios_roi] << {
            scenario: scenario[:scenario_name],
            roi: roi,
            performance_gain: performance_gain,
            effort_cost: effort_cost
          }
        end

        roi_analysis
      end

      def calculate_scenario_roi(scenario)
        performance_gain = scenario[:projected_performance][:improvement_percentage]
        effort_cost = scenario[:estimated_effort_hours]

        return 0.0 if effort_cost <= 0

        (performance_gain / effort_cost * 10).round(2)
      end

      def generate_implementation_roadmap(scenarios)
        # 구현 우선순위와 로드맵 생성
        sorted_scenarios = scenarios.sort_by { |s| -calculate_scenario_roi(s) }

        roadmap = {
          phases: [],
          total_duration: 0,
          total_effort: 0
        }

        sorted_scenarios.each_with_index do |scenario, index|
          phase = {
            phase_number: index + 1,
            scenario_name: scenario[:scenario_name],
            duration_weeks: (scenario[:estimated_effort_hours] / 40.0).ceil,
            effort_hours: scenario[:estimated_effort_hours],
            expected_roi: calculate_scenario_roi(scenario),
            dependencies: []
          }

          roadmap[:phases] << phase
          roadmap[:total_duration] += phase[:duration_weeks]
          roadmap[:total_effort] += phase[:effort_hours]
        end

        roadmap
      end

      def generate_executive_summary(performance_analysis)
        overall_score = performance_analysis[:overall_performance][:overall_score]
        grade = performance_analysis[:overall_performance][:grade]

        {
          overall_assessment: "전체 성능 점수: #{overall_score}/100 (#{PERFORMANCE_GRADES[grade][:description]})",
          key_findings: [
            "#{performance_analysis[:bottleneck_analysis][:critical_bottlenecks].length}개의 중요 병목 지점 발견",
            "#{performance_analysis[:optimization_opportunities].length}개의 최적화 기회 식별",
            "예상 성능 향상 잠재력: #{calculate_total_optimization_potential(performance_analysis)}%"
          ],
          immediate_actions: performance_analysis[:performance_recommendations].select { |r| r[:priority] == "critical" }.map { |r| r[:title] },
          business_impact: assess_business_impact(performance_analysis)
        }
      end

      def generate_detailed_analysis(performance_analysis)
        {
          performance_breakdown: performance_analysis[:overall_performance][:score_breakdown],
          bottleneck_details: performance_analysis[:bottleneck_analysis],
          optimization_details: performance_analysis[:optimization_opportunities],
          risk_analysis: performance_analysis[:risk_assessment]
        }
      end

      def generate_charts_data(performance_analysis)
        {
          performance_score_chart: generate_score_chart_data(performance_analysis),
          bottleneck_distribution_chart: generate_bottleneck_chart_data(performance_analysis),
          optimization_impact_chart: generate_optimization_chart_data(performance_analysis)
        }
      end

      def generate_action_items(performance_analysis)
        action_items = []

        performance_analysis[:performance_recommendations].each do |recommendation|
          recommendation[:actions].each_with_index do |action, index|
            action_items << {
              id: "#{recommendation[:type]}_#{index}",
              title: action,
              priority: recommendation[:priority],
              estimated_effort: recommendation[:estimated_impact],
              category: recommendation[:type],
              deadline: calculate_action_deadline(recommendation[:priority])
            }
          end
        end

        action_items.sort_by { |item| [ priority_weight(item[:priority]), item[:title] ] }
      end

      def generate_report_appendix(performance_analysis)
        {
          technical_details: performance_analysis[:formula_performance],
          methodology: explain_analysis_methodology,
          glossary: provide_performance_glossary,
          references: provide_references
        }
      end

      # 추가 헬퍼 메소드들

      def measure_calculation_time(excel_file)
        # 실제 계산 시간 측정 (예시)
        2500.0 # ms
      end

      def estimate_memory_usage(excel_file)
        # 메모리 사용량 추정 (예시)
        50_000_000 # bytes
      end

      def count_formulas(excel_file)
        # 수식 개수 계산 (예시)
        150
      end

      def count_volatile_functions(excel_file)
        # 휘발성 함수 개수 계산 (예시)
        8
      end

      def calculate_dependency_depth(excel_file)
        # 의존성 깊이 계산 (예시)
        5
      end

      def count_formula_errors(excel_file)
        # 수식 오류 개수 계산 (예시)
        3
      end

      def calculate_total_optimization_potential(performance_analysis)
        opportunities = performance_analysis[:optimization_opportunities]
        return 0 if opportunities.empty?

        (opportunities.sum { |opp| opp[:impact_score] } / opportunities.length * 0.5).round(1)
      end

      def assess_business_impact(performance_analysis)
        overall_score = performance_analysis[:overall_performance][:overall_score]

        case overall_score
        when 0..30
          "심각한 업무 효율성 저하 위험"
        when 31..50
          "업무 생산성에 부정적 영향"
        when 51..70
          "적당한 업무 효율성"
        else
          "우수한 업무 생산성"
        end
      end

      def generate_score_chart_data(performance_analysis)
        # 성능 점수 차트 데이터
        {
          type: "gauge",
          current_score: performance_analysis[:overall_performance][:overall_score],
          target_score: 85.0,
          grade_ranges: PERFORMANCE_GRADES.transform_values { |v| v[:score] }
        }
      end

      def generate_bottleneck_chart_data(performance_analysis)
        # 병목 분포 차트 데이터
        bottlenecks = performance_analysis[:bottleneck_analysis]
        {
          type: "pie",
          data: [
            { label: "Critical Bottlenecks", value: bottlenecks[:critical_bottlenecks].length },
            { label: "Dependency Issues", value: bottlenecks[:dependency_bottlenecks].length },
            { label: "Resource Issues", value: bottlenecks[:resource_bottlenecks].length }
          ]
        }
      end

      def generate_optimization_chart_data(performance_analysis)
        # 최적화 영향도 차트 데이터
        opportunities = performance_analysis[:optimization_opportunities].first(10)
        {
          type: "bar",
          data: opportunities.map do |opp|
            {
              label: opp[:type],
              value: opp[:impact_score]
            }
          end
        }
      end

      def calculate_action_deadline(priority)
        case priority
        when "critical" then 1.week.from_now
        when "high" then 2.weeks.from_now
        when "medium" then 1.month.from_now
        else 3.months.from_now
        end
      end

      def priority_weight(priority)
        case priority
        when "critical" then 1
        when "high" then 2
        when "medium" then 3
        else 4
        end
      end

      def explain_analysis_methodology
        """
        성능 분석 방법론:
        1. 수식별 성능 비용 계산
        2. 병목 지점 식별 및 분류
        3. 최적화 기회 우선순위 결정
        4. ROI 기반 구현 로드맵 제시
        """
      end

      def provide_performance_glossary
        {
          "Performance Score" => "전체 성능을 나타내는 0-100 점수",
          "Bottleneck" => "성능 저하의 주요 원인이 되는 지점",
          "Volatile Function" => "계산 시마다 재평가되는 함수",
          "Array Formula" => "배열 데이터를 처리하는 수식"
        }
      end

      def provide_references
        [
          "Excel Performance Best Practices Guide",
          "Microsoft Excel Calculation Optimization",
          "Spreadsheet Performance Analysis Methods"
        ]
      end
    end
  end
end
