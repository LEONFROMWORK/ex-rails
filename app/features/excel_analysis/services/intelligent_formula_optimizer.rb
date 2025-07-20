# frozen_string_literal: true

module ExcelAnalysis
  module Services
    # 지능형 수식 최적화 엔진
    # 복잡도 분석, 성능 예측, AI 기반 최적화 제안을 통한 자동 수식 개선
    class IntelligentFormulaOptimizer
      include ActiveModel::Model

      # 최적화 오류
      class OptimizationError < StandardError; end
      class PerformanceAnalysisError < StandardError; end
      class RewriteError < StandardError; end

      # 최적화 전략
      OPTIMIZATION_STRATEGIES = {
        function_replacement: {
          priority: "high",
          description: "더 효율적인 함수로 교체"
        },
        range_optimization: {
          priority: "high",
          description: "범위 참조 최적화"
        },
        nesting_reduction: {
          priority: "medium",
          description: "중첩 구조 단순화"
        },
        caching_optimization: {
          priority: "medium",
          description: "중복 계산 제거"
        },
        array_formula_conversion: {
          priority: "low",
          description: "배열 수식 변환"
        }
      }.freeze

      # 함수별 성능 특성
      FUNCTION_PERFORMANCE_MAP = {
        "VLOOKUP" => {
          complexity: "O(n)",
          alternatives: [ "XLOOKUP", "INDEX+MATCH" ],
          performance_factor: 3.0
        },
        "HLOOKUP" => {
          complexity: "O(n)",
          alternatives: [ "XLOOKUP", "INDEX+MATCH" ],
          performance_factor: 3.0
        },
        "SUMPRODUCT" => {
          complexity: "O(n²)",
          alternatives: [ "SUMIFS", "COUNTIFS" ],
          performance_factor: 5.0
        },
        "OFFSET" => {
          complexity: "O(1)",
          alternatives: [ "INDEX" ],
          performance_factor: 2.0
        },
        "INDIRECT" => {
          complexity: "O(1)",
          alternatives: [ "Direct Reference" ],
          performance_factor: 4.0
        }
      }.freeze

      attr_reader :formula_engine_client, :ai_service, :optimization_cache

      def initialize
        @formula_engine_client = FormulaEngineClient.instance
        @ai_service = Features::AiIntegration::Services::ModernizedMultiProviderService.new
        @optimization_cache = {}
      end

      # 수식 최적화 수행
      # @param formula [String] 최적화할 수식
      # @param context [Hash] 최적화 컨텍스트
      # @param strategies [Array] 적용할 최적화 전략
      # @return [Common::Result] 최적화 결과
      def optimize_formula(formula, context = {}, strategies = OPTIMIZATION_STRATEGIES.keys)
        Rails.logger.info("수식 최적화 시작: #{formula[0..50]}...")

        # 캐시 확인
        cache_key = generate_cache_key(formula, context, strategies)
        if @optimization_cache.key?(cache_key)
          Rails.logger.info("캐시된 최적화 결과 반환")
          return Common::Result.success(@optimization_cache[cache_key])
        end

        optimization_result = {
          original_formula: formula,
          optimized_formulas: [],
          performance_analysis: {},
          optimization_strategies_applied: [],
          estimated_performance_gain: 0.0,
          complexity_reduction: 0.0,
          risk_assessment: {},
          recommendations: []
        }

        begin
          # 1. 원본 수식 성능 분석
          original_analysis = analyze_formula_performance(formula, context)
          return original_analysis if original_analysis.failure?

          optimization_result[:performance_analysis][:original] = original_analysis.value

          # 2. 각 최적화 전략 적용
          optimized_candidates = []

          strategies.each do |strategy|
            strategy_result = apply_optimization_strategy(formula, strategy, context)

            if strategy_result.success? && strategy_result.value[:optimized_formula]
              candidate = strategy_result.value
              candidate[:strategy] = strategy
              candidate[:priority] = OPTIMIZATION_STRATEGIES[strategy][:priority]

              # 최적화된 수식 성능 분석
              optimized_analysis = analyze_formula_performance(
                candidate[:optimized_formula],
                context
              )

              if optimized_analysis.success?
                candidate[:performance_analysis] = optimized_analysis.value
                candidate[:performance_gain] = calculate_performance_gain(
                  original_analysis.value,
                  optimized_analysis.value
                )

                optimized_candidates << candidate if candidate[:performance_gain] > 0
              end
            end
          end

          # 3. 최적 후보 선택 및 순위 결정
          ranked_candidates = rank_optimization_candidates(optimized_candidates)
          optimization_result[:optimized_formulas] = ranked_candidates

          # 4. 최종 추천 결정
          if ranked_candidates.any?
            best_candidate = ranked_candidates.first
            optimization_result[:recommended_formula] = best_candidate[:optimized_formula]
            optimization_result[:estimated_performance_gain] = best_candidate[:performance_gain]
            optimization_result[:optimization_strategies_applied] = ranked_candidates.map { |c| c[:strategy] }

            # 복잡도 감소 계산
            optimization_result[:complexity_reduction] = calculate_complexity_reduction(
              original_analysis.value[:complexity_score],
              best_candidate[:performance_analysis][:complexity_score]
            )
          end

          # 5. 위험도 평가
          optimization_result[:risk_assessment] = assess_optimization_risk(
            formula,
            optimization_result[:recommended_formula],
            context
          )

          # 6. 추가 권장사항 생성
          optimization_result[:recommendations] = generate_optimization_recommendations(
            optimization_result
          )

          # 결과 캐시 저장
          @optimization_cache[cache_key] = optimization_result

          Common::Result.success(optimization_result)

        rescue StandardError => e
          Rails.logger.error("수식 최적화 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "수식 최적화 실패: #{e.message}",
              code: "FORMULA_OPTIMIZATION_ERROR",
              details: { formula: formula, context: context }
            )
          )
        end
      end

      # 일괄 최적화 (워크북 전체)
      # @param excel_file [ExcelFile] 최적화할 Excel 파일
      # @param options [Hash] 최적화 옵션
      # @return [Common::Result] 일괄 최적화 결과
      def optimize_workbook(excel_file, options = {})
        Rails.logger.info("워크북 일괄 최적화 시작: #{excel_file.id}")

        workbook_optimization = {
          total_formulas: 0,
          optimized_formulas: 0,
          total_performance_gain: 0.0,
          optimization_summary: {},
          detailed_results: [],
          high_impact_optimizations: [],
          recommendations: []
        }

        begin
          # Excel 분석 수행
          analysis_service = FormulaAnalysisService.new(excel_file)
          analysis_result = analysis_service.analyze
          return analysis_result if analysis_result.failure?

          formula_data = analysis_result.value[:formula_analysis]
          workbook_optimization[:total_formulas] = extract_total_formulas(formula_data)

          # 수식별 최적화 수행
          if formula_data&.dig("formulas")
            process_formulas_for_optimization(
              formula_data["formulas"],
              workbook_optimization,
              options
            )
          end

          # 최적화 요약 생성
          generate_workbook_optimization_summary(workbook_optimization)

          Common::Result.success(workbook_optimization)

        rescue StandardError => e
          Rails.logger.error("워크북 최적화 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "워크북 최적화 실패: #{e.message}",
              code: "WORKBOOK_OPTIMIZATION_ERROR",
              details: { excel_file_id: excel_file.id }
            )
          )
        end
      end

      # 성능 예측
      # @param formula [String] 성능을 예측할 수식
      # @param context [Hash] 컨텍스트 정보
      # @return [Common::Result] 성능 예측 결과
      def predict_performance(formula, context = {})
        Rails.logger.info("성능 예측 시작: #{formula[0..30]}...")

        begin
          performance_prediction = {
            formula: formula,
            estimated_calculation_time: 0.0,
            memory_usage_estimate: 0.0,
            complexity_factors: {},
            performance_bottlenecks: [],
            scalability_analysis: {},
            optimization_potential: 0.0
          }

          # 복잡도 팩터 분석
          complexity_factors = analyze_complexity_factors(formula)
          performance_prediction[:complexity_factors] = complexity_factors

          # 계산 시간 예측
          estimated_time = predict_calculation_time(formula, complexity_factors, context)
          performance_prediction[:estimated_calculation_time] = estimated_time

          # 메모리 사용량 예측
          memory_estimate = predict_memory_usage(formula, complexity_factors, context)
          performance_prediction[:memory_usage_estimate] = memory_estimate

          # 성능 병목 식별
          bottlenecks = identify_performance_bottlenecks(formula, complexity_factors)
          performance_prediction[:performance_bottlenecks] = bottlenecks

          # 확장성 분석
          scalability = analyze_scalability(formula, context)
          performance_prediction[:scalability_analysis] = scalability

          # 최적화 잠재력 계산
          optimization_potential = calculate_optimization_potential(
            complexity_factors,
            bottlenecks
          )
          performance_prediction[:optimization_potential] = optimization_potential

          Common::Result.success(performance_prediction)

        rescue StandardError => e
          Rails.logger.error("성능 예측 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "성능 예측 실패: #{e.message}",
              code: "PERFORMANCE_PREDICTION_ERROR",
              details: { formula: formula }
            )
          )
        end
      end

      private

      # 수식 성능 분석
      def analyze_formula_performance(formula, context)
        analysis = {
          complexity_score: 0.0,
          estimated_calculation_time: 0.0,
          memory_usage: 0.0,
          function_analysis: {},
          reference_analysis: {},
          bottlenecks: []
        }

        # 복잡도 점수 계산
        analysis[:complexity_score] = calculate_detailed_complexity_score(formula)

        # 함수 분석
        functions = extract_functions_with_details(formula)
        analysis[:function_analysis] = analyze_function_performance(functions)

        # 참조 분석
        references = extract_references_with_details(formula)
        analysis[:reference_analysis] = analyze_reference_performance(references, context)

        # 계산 시간 예측
        analysis[:estimated_calculation_time] = predict_calculation_time(
          formula,
          analysis,
          context
        )

        # 메모리 사용량 예측
        analysis[:memory_usage] = predict_memory_usage(formula, analysis, context)

        # 병목 지점 식별
        analysis[:bottlenecks] = identify_performance_bottlenecks(formula, analysis)

        Common::Result.success(analysis)
      end

      # 최적화 전략 적용
      def apply_optimization_strategy(formula, strategy, context)
        case strategy
        when :function_replacement
          apply_function_replacement_strategy(formula, context)
        when :range_optimization
          apply_range_optimization_strategy(formula, context)
        when :nesting_reduction
          apply_nesting_reduction_strategy(formula, context)
        when :caching_optimization
          apply_caching_optimization_strategy(formula, context)
        when :array_formula_conversion
          apply_array_formula_conversion_strategy(formula, context)
        else
          Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "알 수 없는 최적화 전략: #{strategy}"
            )
          )
        end
      end

      # 함수 교체 전략
      def apply_function_replacement_strategy(formula, context)
        optimizations = []

        FUNCTION_PERFORMANCE_MAP.each do |func_name, func_info|
          if formula.upcase.include?(func_name)
            func_info[:alternatives].each do |alternative|
              optimized = replace_function(formula, func_name, alternative)
              if optimized != formula
                optimizations << {
                  optimized_formula: optimized,
                  strategy_details: {
                    original_function: func_name,
                    replacement_function: alternative,
                    expected_improvement: func_info[:performance_factor]
                  }
                }
              end
            end
          end
        end

        best_optimization = optimizations.max_by do |opt|
          opt[:strategy_details][:expected_improvement]
        end

        if best_optimization
          Common::Result.success(best_optimization)
        else
          Common::Result.success({ optimized_formula: nil })
        end
      end

      # 범위 최적화 전략
      def apply_range_optimization_strategy(formula, context)
        # 불필요하게 큰 범위 참조 최적화
        optimized = optimize_range_references(formula, context)

        if optimized != formula
          Common::Result.success({
            optimized_formula: optimized,
            strategy_details: {
              optimization_type: "range_reduction",
              description: "범위 참조를 필요한 크기로 축소"
            }
          })
        else
          Common::Result.success({ optimized_formula: nil })
        end
      end

      # 중첩 감소 전략
      def apply_nesting_reduction_strategy(formula, context)
        if calculate_max_nesting_depth(formula) > 5
          # 중첩된 수식을 여러 단계로 분할하는 제안
          optimized = suggest_nesting_reduction(formula)

          Common::Result.success({
            optimized_formula: optimized,
            strategy_details: {
              optimization_type: "nesting_reduction",
              description: "복잡한 중첩을 단순한 단계로 분할",
              requires_helper_cells: true
            }
          })
        else
          Common::Result.success({ optimized_formula: nil })
        end
      end

      # 캐싱 최적화 전략
      def apply_caching_optimization_strategy(formula, context)
        # 중복 계산 식별 및 최적화
        duplicates = find_duplicate_calculations(formula)

        if duplicates.any?
          optimized = optimize_duplicate_calculations(formula, duplicates)

          Common::Result.success({
            optimized_formula: optimized,
            strategy_details: {
              optimization_type: "caching",
              description: "중복 계산 제거",
              duplicate_count: duplicates.length
            }
          })
        else
          Common::Result.success({ optimized_formula: nil })
        end
      end

      # 배열 수식 변환 전략
      def apply_array_formula_conversion_strategy(formula, context)
        # 반복적인 계산을 배열 수식으로 변환
        if can_convert_to_array_formula?(formula)
          optimized = convert_to_array_formula(formula)

          Common::Result.success({
            optimized_formula: optimized,
            strategy_details: {
              optimization_type: "array_conversion",
              description: "반복 계산을 배열 수식으로 변환"
            }
          })
        else
          Common::Result.success({ optimized_formula: nil })
        end
      end

      # 최적화 후보 순위 결정
      def rank_optimization_candidates(candidates)
        candidates.sort_by do |candidate|
          priority_weight = case candidate[:priority]
          when "high" then 3.0
          when "medium" then 2.0
          when "low" then 1.0
          else 0.5
          end

          -(candidate[:performance_gain] * priority_weight)
        end
      end

      # 성능 향상도 계산
      def calculate_performance_gain(original_analysis, optimized_analysis)
        original_time = original_analysis[:estimated_calculation_time]
        optimized_time = optimized_analysis[:estimated_calculation_time]

        return 0.0 if original_time <= 0

        ((original_time - optimized_time) / original_time * 100).round(2)
      end

      # 복잡도 감소율 계산
      def calculate_complexity_reduction(original_complexity, optimized_complexity)
        return 0.0 if original_complexity <= 0

        ((original_complexity - optimized_complexity) / original_complexity * 100).round(2)
      end

      # 최적화 위험도 평가
      def assess_optimization_risk(original_formula, optimized_formula, context)
        return { risk_level: "none" } unless optimized_formula

        risk_assessment = {
          risk_level: "low",
          risk_factors: [],
          mitigation_strategies: []
        }

        # 함수 변경 위험
        original_functions = extract_functions_with_details(original_formula)
        optimized_functions = extract_functions_with_details(optimized_formula)

        if original_functions != optimized_functions
          risk_assessment[:risk_factors] << {
            type: "function_change",
            description: "함수가 변경되었습니다.",
            severity: "medium"
          }

          risk_assessment[:mitigation_strategies] << "변경된 함수의 동작을 충분히 테스트하세요."
          risk_assessment[:risk_level] = "medium"
        end

        # 참조 변경 위험
        if reference_patterns_changed?(original_formula, optimized_formula)
          risk_assessment[:risk_factors] << {
            type: "reference_change",
            description: "참조 패턴이 변경되었습니다.",
            severity: "high"
          }

          risk_assessment[:mitigation_strategies] << "참조 범위를 검증하고 예상 결과와 비교하세요."
          risk_assessment[:risk_level] = "high"
        end

        risk_assessment
      end

      # 최적화 권장사항 생성
      def generate_optimization_recommendations(optimization_result)
        recommendations = []

        if optimization_result[:estimated_performance_gain] > 50
          recommendations << {
            type: "high_impact",
            priority: "high",
            message: "상당한 성능 향상(#{optimization_result[:estimated_performance_gain]}%)이 예상됩니다.",
            action: "최적화 적용을 강력히 권장합니다."
          }
        elsif optimization_result[:estimated_performance_gain] > 20
          recommendations << {
            type: "medium_impact",
            priority: "medium",
            message: "적당한 성능 향상(#{optimization_result[:estimated_performance_gain]}%)이 예상됩니다.",
            action: "최적화 적용을 고려해보세요."
          }
        end

        if optimization_result[:complexity_reduction] > 30
          recommendations << {
            type: "maintainability",
            priority: "medium",
            message: "수식 복잡도가 #{optimization_result[:complexity_reduction]}% 감소합니다.",
            action: "유지보수성 향상을 위해 적용을 고려하세요."
          }
        end

        if optimization_result[:risk_assessment][:risk_level] == "high"
          recommendations << {
            type: "risk_warning",
            priority: "high",
            message: "높은 위험도가 감지되었습니다.",
            action: "충분한 테스트 후 신중하게 적용하세요."
          }
        end

        recommendations
      end

      # 헬퍼 메소드들

      def generate_cache_key(formula, context, strategies)
        Digest::MD5.hexdigest("#{formula}:#{context}:#{strategies.join(',')}")
      end

      def extract_total_formulas(formula_data)
        formula_data&.dig("summary", "totalFormulas") || 0
      end

      def process_formulas_for_optimization(formulas, workbook_optimization, options)
        formulas.each do |formula_info|
          optimization_result = optimize_formula(
            formula_info["formula"],
            {
              cell: formula_info["cell"],
              sheet: formula_info["sheet"]
            },
            options[:strategies] || OPTIMIZATION_STRATEGIES.keys
          )

          if optimization_result.success?
            result = optimization_result.value
            workbook_optimization[:detailed_results] << result

            if result[:estimated_performance_gain] > 0
              workbook_optimization[:optimized_formulas] += 1
              workbook_optimization[:total_performance_gain] += result[:estimated_performance_gain]

              if result[:estimated_performance_gain] > 30
                workbook_optimization[:high_impact_optimizations] << result
              end
            end
          end
        end
      end

      def generate_workbook_optimization_summary(workbook_optimization)
        summary = {}

        if workbook_optimization[:optimized_formulas] > 0
          summary[:average_performance_gain] = (
            workbook_optimization[:total_performance_gain] /
            workbook_optimization[:optimized_formulas]
          ).round(2)

          summary[:optimization_rate] = (
            workbook_optimization[:optimized_formulas].to_f /
            workbook_optimization[:total_formulas] * 100
          ).round(2)
        end

        workbook_optimization[:optimization_summary] = summary
      end

      def calculate_detailed_complexity_score(formula)
        # AdvancedFormulaValidator와 동일한 로직 사용
        validator = AdvancedFormulaValidator.new
        validator.send(:calculate_complexity_score, formula)
      end

      def extract_functions_with_details(formula)
        formula.scan(/([A-Z][A-Z0-9\.]*)\s*\(/).flatten.uniq
      end

      def extract_references_with_details(formula)
        formula.scan(/[A-Z]+\d+(?::[A-Z]+\d+)?/)
      end

      def analyze_function_performance(functions)
        analysis = {}

        functions.each do |func|
          if FUNCTION_PERFORMANCE_MAP.key?(func)
            analysis[func] = FUNCTION_PERFORMANCE_MAP[func]
          else
            analysis[func] = { complexity: "O(1)", performance_factor: 1.0 }
          end
        end

        analysis
      end

      def analyze_reference_performance(references, context)
        total_cells = references.sum do |ref|
          if ref.include?(":")
            # 범위 참조 크기 추정
            estimate_range_size(ref)
          else
            1
          end
        end

        {
          total_references: references.length,
          estimated_cells: total_cells,
          has_large_ranges: total_cells > 10000
        }
      end

      def predict_calculation_time(formula, analysis, context)
        base_time = 1.0 # ms

        # 함수별 계산 시간 추가
        if analysis[:function_analysis]
          analysis[:function_analysis].each do |func, info|
            base_time += info[:performance_factor] || 1.0
          end
        end

        # 참조 크기에 따른 시간 추가
        if analysis[:reference_analysis]
          base_time += analysis[:reference_analysis][:estimated_cells] / 1000.0
        end

        # 복잡도에 따른 가중치
        complexity_multiplier = 1 + (analysis[:complexity_score] || 0) / 10.0

        (base_time * complexity_multiplier).round(2)
      end

      def predict_memory_usage(formula, analysis, context)
        base_memory = 100 # bytes

        # 참조 크기에 따른 메모리 추가
        if analysis[:reference_analysis]
          base_memory += analysis[:reference_analysis][:estimated_cells] * 8 # 8 bytes per cell
        end

        base_memory
      end

      def identify_performance_bottlenecks(formula, analysis)
        bottlenecks = []

        # 고비용 함수 식별
        if analysis[:function_analysis]
          analysis[:function_analysis].each do |func, info|
            if info[:performance_factor] && info[:performance_factor] > 3.0
              bottlenecks << {
                type: "expensive_function",
                function: func,
                impact: "high",
                suggestion: "#{func} 함수를 더 효율적인 대안으로 교체 고려"
              }
            end
          end
        end

        # 큰 범위 참조 식별
        if analysis[:reference_analysis] && analysis[:reference_analysis][:has_large_ranges]
          bottlenecks << {
            type: "large_range",
            impact: "medium",
            suggestion: "범위 크기를 줄이거나 더 정확한 참조 사용"
          }
        end

        bottlenecks
      end

      def replace_function(formula, old_func, new_func)
        # 간단한 함수 교체 (실제로는 더 정교한 파싱 필요)
        formula.gsub(/#{old_func}\s*\(/i, "#{new_func}(")
      end

      def optimize_range_references(formula, context)
        # 범위 최적화 로직 (예시)
        formula
      end

      def suggest_nesting_reduction(formula)
        # 중첩 감소 제안 (예시)
        "<!-- 중첩 감소를 위해 헬퍼 셀 사용 권장 -->"
      end

      def find_duplicate_calculations(formula)
        # 중복 계산 식별 (예시)
        []
      end

      def optimize_duplicate_calculations(formula, duplicates)
        # 중복 계산 최적화 (예시)
        formula
      end

      def can_convert_to_array_formula?(formula)
        # 배열 수식 변환 가능성 확인
        false
      end

      def convert_to_array_formula(formula)
        # 배열 수식으로 변환
        formula
      end

      def reference_patterns_changed?(original, optimized)
        original_refs = extract_references_with_details(original)
        optimized_refs = extract_references_with_details(optimized)
        original_refs != optimized_refs
      end

      def calculate_max_nesting_depth(formula)
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

      def estimate_range_size(range_ref)
        # 범위 크기 추정 (단순화된 버전)
        if range_ref.include?(":")
          100 # 예시 값
        else
          1
        end
      end

      def analyze_complexity_factors(formula)
        {
          formula_length: formula.length,
          function_count: extract_functions_with_details(formula).length,
          reference_count: extract_references_with_details(formula).length,
          nesting_depth: calculate_max_nesting_depth(formula)
        }
      end

      def analyze_scalability(formula, context)
        {
          data_size_sensitivity: "medium",
          memory_scalability: "good",
          performance_scalability: "fair"
        }
      end

      def calculate_optimization_potential(complexity_factors, bottlenecks)
        base_potential = 0.0

        # 복잡도 팩터 기반 잠재력
        base_potential += complexity_factors[:function_count] * 5.0
        base_potential += complexity_factors[:nesting_depth] * 10.0

        # 병목 지점 기반 잠재력
        base_potential += bottlenecks.length * 15.0

        [ base_potential, 100.0 ].min
      end
    end
  end
end
