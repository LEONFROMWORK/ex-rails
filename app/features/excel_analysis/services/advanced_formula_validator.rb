# frozen_string_literal: true

module ExcelAnalysis
  module Services
    # 실시간 수식 검증 및 지능형 제안 시스템
    # HyperFormula와 AI를 결합한 고급 수식 검증 및 최적화 제안
    class AdvancedFormulaValidator
      include ActiveModel::Model

      # 수식 검증 오류
      class ValidationError < StandardError; end
      class FormulaParsingError < StandardError; end
      class PerformanceError < StandardError; end

      COMPLEXITY_THRESHOLDS = {
        low: 2.0,
        medium: 4.0,
        high: 7.0,
        critical: 10.0
      }.freeze

      PERFORMANCE_RISK_FUNCTIONS = %w[
        VLOOKUP HLOOKUP INDEX MATCH OFFSET INDIRECT
        SUMPRODUCT SUMIFS COUNTIFS AVERAGEIFS
        ARRAY LAMBDA LET FILTER SORT UNIQUE
      ].freeze

      attr_reader :formula_engine_client, :ai_service

      def initialize
        @formula_engine_client = FormulaEngineClient.instance
        @ai_service = Features::AiIntegration::Services::ModernizedMultiProviderService.new
      end

      # 실시간 수식 검증
      # @param formula [String] 검증할 수식
      # @param context [Hash] 수식 컨텍스트 (셀 위치, 워크시트 정보 등)
      # @return [Common::Result] 검증 결과
      def validate_formula_realtime(formula, context = {})
        Rails.logger.info("실시간 수식 검증 시작: #{formula[0..50]}...")

        validation_result = {
          formula: formula,
          is_valid: false,
          syntax_errors: [],
          semantic_errors: [],
          performance_warnings: [],
          optimization_suggestions: [],
          complexity_score: 0.0,
          risk_level: "low",
          estimated_calculation_time: 0,
          alternative_formulas: [],
          best_practices_violations: []
        }

        begin
          # 1. 기본 구문 검증
          syntax_result = validate_syntax(formula, context)
          return syntax_result if syntax_result.failure?

          validation_result.merge!(syntax_result.value)

          # 2. 의미적 검증 (참조 무결성, 순환 참조 등)
          semantic_result = validate_semantics(formula, context)
          validation_result.merge!(semantic_result.value) if semantic_result.success?

          # 3. 성능 분석
          performance_result = analyze_performance(formula, context)
          validation_result.merge!(performance_result.value) if performance_result.success?

          # 4. 복잡도 계산
          validation_result[:complexity_score] = calculate_complexity_score(formula)
          validation_result[:risk_level] = determine_risk_level(validation_result[:complexity_score])

          # 5. 최적화 제안 생성
          optimization_result = generate_optimization_suggestions(formula, validation_result)
          validation_result[:optimization_suggestions] = optimization_result.value if optimization_result.success?

          # 6. 대안 수식 제안 (AI 기반)
          if context[:enable_ai_suggestions]
            alternative_result = generate_alternative_formulas(formula, context)
            validation_result[:alternative_formulas] = alternative_result.value if alternative_result.success?
          end

          # 7. 모범 사례 검증
          validation_result[:best_practices_violations] = check_best_practices(formula)

          validation_result[:is_valid] = validation_result[:syntax_errors].empty? &&
                                        validation_result[:semantic_errors].empty?

          Common::Result.success(validation_result)

        rescue StandardError => e
          Rails.logger.error("수식 검증 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "수식 검증 실패: #{e.message}",
              code: "FORMULA_VALIDATION_ERROR",
              details: { formula: formula, context: context }
            )
          )
        end
      end

      # 일괄 수식 검증 (Excel 파일 전체)
      # @param excel_file [ExcelFile] 검증할 Excel 파일
      # @param options [Hash] 검증 옵션
      # @return [Common::Result] 일괄 검증 결과
      def validate_workbook_formulas(excel_file, options = {})
        Rails.logger.info("일괄 수식 검증 시작: #{excel_file.id}")

        validation_summary = {
          total_formulas: 0,
          valid_formulas: 0,
          invalid_formulas: 0,
          high_risk_formulas: 0,
          optimization_opportunities: 0,
          estimated_performance_gain: 0.0,
          detailed_results: [],
          summary_statistics: {},
          recommendations: []
        }

        begin
          # Excel 분석 수행
          analysis_service = FormulaAnalysisService.new(excel_file)
          analysis_result = analysis_service.analyze
          return analysis_result if analysis_result.failure?

          formula_data = analysis_result.value[:formula_analysis]
          validation_summary[:total_formulas] = extract_total_formulas(formula_data)

          # 각 수식별 개별 검증
          if formula_data&.dig("formulas")
            formula_data["formulas"].each do |formula_info|
              formula_result = validate_formula_realtime(
                formula_info["formula"],
                {
                  cell: formula_info["cell"],
                  sheet: formula_info["sheet"],
                  enable_ai_suggestions: options[:enable_ai_suggestions]
                }
              )

              if formula_result.success?
                result = formula_result.value
                validation_summary[:detailed_results] << result

                update_summary_statistics(validation_summary, result)
              end
            end
          end

          # 전체 요약 및 권장사항 생성
          validation_summary[:recommendations] = generate_workbook_recommendations(validation_summary)

          Common::Result.success(validation_summary)

        rescue StandardError => e
          Rails.logger.error("일괄 수식 검증 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "일괄 수식 검증 실패: #{e.message}",
              code: "WORKBOOK_VALIDATION_ERROR",
              details: { excel_file_id: excel_file.id }
            )
          )
        end
      end

      # 수식 실시간 미리보기
      # @param formula [String] 미리보기할 수식
      # @param sample_data [Hash] 샘플 데이터
      # @return [Common::Result] 미리보기 결과
      def preview_formula_result(formula, sample_data = {})
        Rails.logger.info("수식 미리보기 시작: #{formula[0..30]}...")

        begin
          # FormulaEngine을 통한 계산
          calculation_result = @formula_engine_client.calculate_formula_with_session(formula)
          return calculation_result if calculation_result.failure?

          preview_result = {
            formula: formula,
            calculated_value: calculation_result.value[:result],
            data_type: determine_value_type(calculation_result.value[:result]),
            calculation_time: measure_calculation_time(formula),
            explanation: generate_formula_explanation(formula),
            step_by_step: break_down_formula_steps(formula)
          }

          Common::Result.success(preview_result)

        rescue StandardError => e
          Rails.logger.error("수식 미리보기 실패: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "수식 미리보기 실패: #{e.message}",
              code: "FORMULA_PREVIEW_ERROR",
              details: { formula: formula }
            )
          )
        end
      end

      private

      # 구문 검증
      def validate_syntax(formula, context)
        validation_result = @formula_engine_client.validate_formula_with_session(formula)
        return validation_result if validation_result.failure?

        result = validation_result.value

        syntax_result = {
          is_syntactically_valid: result[:valid],
          syntax_errors: result[:errors] || []
        }

        Common::Result.success(syntax_result)
      end

      # 의미적 검증
      def validate_semantics(formula, context)
        semantic_issues = []

        # 순환 참조 검사
        if contains_circular_reference?(formula, context)
          semantic_issues << {
            type: "circular_reference",
            severity: "error",
            message: "순환 참조가 감지되었습니다.",
            suggestion: "수식에서 자기 자신을 참조하지 않도록 수정하세요."
          }
        end

        # 잘못된 참조 검사
        invalid_refs = find_invalid_references(formula, context)
        invalid_refs.each do |ref|
          semantic_issues << {
            type: "invalid_reference",
            severity: "error",
            message: "잘못된 참조: #{ref}",
            suggestion: "존재하는 셀이나 범위를 참조하도록 수정하세요."
          }
        end

        # 데이터 타입 불일치 검사
        type_mismatches = check_data_type_consistency(formula, context)
        semantic_issues.concat(type_mismatches)

        Common::Result.success({
          semantic_errors: semantic_issues
        })
      end

      # 성능 분석
      def analyze_performance(formula, context)
        performance_warnings = []
        estimated_time = 0

        # 고위험 함수 사용 검사
        PERFORMANCE_RISK_FUNCTIONS.each do |risk_func|
          if formula.upcase.include?(risk_func)
            performance_warnings << {
              type: "performance_risk",
              function: risk_func,
              severity: "warning",
              message: "#{risk_func} 함수는 성능에 영향을 줄 수 있습니다.",
              suggestion: get_performance_alternative(risk_func)
            }
            estimated_time += estimate_function_calculation_time(risk_func)
          end
        end

        # 복잡한 범위 참조 검사
        range_complexity = analyze_range_complexity(formula)
        if range_complexity[:is_complex]
          performance_warnings << {
            type: "complex_range",
            severity: "warning",
            message: "복잡한 범위 참조가 감지되었습니다.",
            suggestion: "범위를 더 작게 나누거나 인덱스를 사용하는 것을 고려하세요.",
            details: range_complexity
          }
          estimated_time += range_complexity[:estimated_time]
        end

        # 중첩 함수 분석
        nesting_analysis = analyze_function_nesting(formula)
        if nesting_analysis[:max_depth] > 5
          performance_warnings << {
            type: "deep_nesting",
            severity: "warning",
            message: "과도한 함수 중첩이 감지되었습니다.",
            suggestion: "수식을 여러 단계로 나누는 것을 고려하세요.",
            details: nesting_analysis
          }
          estimated_time += nesting_analysis[:estimated_time]
        end

        Common::Result.success({
          performance_warnings: performance_warnings,
          estimated_calculation_time: estimated_time
        })
      end

      # 복잡도 점수 계산
      def calculate_complexity_score(formula)
        return 0.0 if formula.blank?

        score = 0.0

        # 기본 길이 점수
        score += formula.length / 100.0

        # 함수 개수
        functions = extract_functions(formula)
        score += functions.length * 0.5

        # 복잡한 함수 가중치
        complex_functions = functions.select { |f| PERFORMANCE_RISK_FUNCTIONS.include?(f.upcase) }
        score += complex_functions.length * 1.0

        # 참조 개수
        references = extract_references(formula)
        score += references.length * 0.3

        # 범위 참조 가중치
        range_refs = references.select { |ref| ref.include?(":") }
        score += range_refs.length * 0.5

        # 중첩 깊이
        nesting_depth = calculate_max_nesting_depth(formula)
        score += nesting_depth * 1.0

        # 논리 연산자
        logical_ops = formula.scan(/[<>=!]+/).length
        score += logical_ops * 0.2

        [ score, 15.0 ].min.round(2)
      end

      # 위험도 수준 결정
      def determine_risk_level(complexity_score)
        case complexity_score
        when 0...COMPLEXITY_THRESHOLDS[:low] then "low"
        when COMPLEXITY_THRESHOLDS[:low]...COMPLEXITY_THRESHOLDS[:medium] then "medium"
        when COMPLEXITY_THRESHOLDS[:medium]...COMPLEXITY_THRESHOLDS[:high] then "high"
        else "critical"
        end
      end

      # 최적화 제안 생성
      def generate_optimization_suggestions(formula, validation_result)
        suggestions = []

        # VLOOKUP → XLOOKUP 제안
        if formula.upcase.include?("VLOOKUP")
          suggestions << {
            type: "function_upgrade",
            current: "VLOOKUP",
            suggested: "XLOOKUP",
            reason: "XLOOKUP은 더 유연하고 성능이 좋습니다.",
            example: convert_vlookup_to_xlookup(formula),
            priority: "medium"
          }
        end

        # 중첩 함수 단순화 제안
        if validation_result[:complexity_score] > COMPLEXITY_THRESHOLDS[:medium]
          suggestions << {
            type: "complexity_reduction",
            reason: "복잡한 수식을 단순화하면 가독성과 성능이 향상됩니다.",
            suggestion: "수식을 여러 단계로 나누거나 헬퍼 컬럼을 사용하세요.",
            priority: "high"
          }
        end

        # 하드코딩 값 개선 제안
        hardcoded_values = find_hardcoded_values(formula)
        if hardcoded_values.any?
          suggestions << {
            type: "maintainability",
            reason: "하드코딩된 값은 유지보수를 어렵게 만듭니다.",
            suggestion: "이름 정의나 별도 셀 참조를 사용하세요.",
            hardcoded_values: hardcoded_values,
            priority: "medium"
          }
        end

        # 성능 최적화 제안
        if validation_result[:estimated_calculation_time] > 100 # ms
          suggestions << {
            type: "performance_optimization",
            reason: "계산 시간이 오래 걸릴 수 있습니다.",
            suggestion: "범위를 줄이거나 더 효율적인 함수를 사용하세요.",
            estimated_savings: "#{validation_result[:estimated_calculation_time] * 0.3}ms",
            priority: "high"
          }
        end

        Common::Result.success(suggestions)
      end

      # AI 기반 대안 수식 생성
      def generate_alternative_formulas(formula, context)
        return Common::Result.success([]) unless formula.present?

        begin
          prompt = build_ai_formula_prompt(formula, context)

          ai_result = @ai_service.process_request(
            prompt: prompt,
            context: "formula_optimization",
            options: {
              max_tokens: 1000,
              temperature: 0.3
            }
          )

          return ai_result if ai_result.failure?

          alternatives = parse_ai_formula_response(ai_result.value[:response])

          Common::Result.success(alternatives)

        rescue StandardError => e
          Rails.logger.warn("AI 수식 제안 실패: #{e.message}")
          Common::Result.success([])
        end
      end

      # 모범 사례 검증
      def check_best_practices(formula)
        violations = []

        # 1. 너무 긴 수식
        if formula.length > 255
          violations << {
            rule: "formula_length",
            message: "수식이 너무 깁니다 (255자 초과).",
            suggestion: "수식을 여러 단계로 나누세요."
          }
        end

        # 2. 과도한 중첩
        if calculate_max_nesting_depth(formula) > 7
          violations << {
            rule: "excessive_nesting",
            message: "함수 중첩이 과도합니다.",
            suggestion: "중간 계산을 별도 셀에 저장하세요."
          }
        end

        # 3. 모호한 참조
        if formula.match?(/[A-Z]+\d+:\w+\d+/)
          violations << {
            rule: "ambiguous_references",
            message: "모호한 범위 참조가 있습니다.",
            suggestion: "명확한 범위나 이름 정의를 사용하세요."
          }
        end

        # 4. 하드코딩된 날짜
        if formula.match?(/"\d{4}-\d{2}-\d{2}"|\d{1,2}\/\d{1,2}\/\d{4}/)
          violations << {
            rule: "hardcoded_dates",
            message: "하드코딩된 날짜가 발견되었습니다.",
            suggestion: "DATE 함수나 셀 참조를 사용하세요."
          }
        end

        violations
      end

      # 헬퍼 메소드들

      def extract_total_formulas(formula_data)
        formula_data&.dig("summary", "totalFormulas") || 0
      end

      def update_summary_statistics(summary, result)
        summary[:valid_formulas] += 1 if result[:is_valid]
        summary[:invalid_formulas] += 1 unless result[:is_valid]
        summary[:high_risk_formulas] += 1 if result[:risk_level] == "high" || result[:risk_level] == "critical"
        summary[:optimization_opportunities] += result[:optimization_suggestions].length
      end

      def generate_workbook_recommendations(summary)
        recommendations = []

        if summary[:high_risk_formulas] > 0
          recommendations << {
            type: "risk_reduction",
            priority: "high",
            message: "#{summary[:high_risk_formulas]}개의 고위험 수식이 발견되었습니다.",
            action: "수식 복잡도를 줄이고 성능을 최적화하세요."
          }
        end

        if summary[:optimization_opportunities] > 10
          recommendations << {
            type: "optimization",
            priority: "medium",
            message: "#{summary[:optimization_opportunities]}개의 최적화 기회가 있습니다.",
            action: "제안된 최적화를 적용하여 성능을 향상시키세요."
          }
        end

        recommendations
      end

      def contains_circular_reference?(formula, context)
        return false unless context[:cell]
        formula.include?(context[:cell])
      end

      def find_invalid_references(formula, context)
        # 간단한 참조 추출 (실제로는 더 정교한 파싱 필요)
        references = formula.scan(/[A-Z]+\d+(?::[A-Z]+\d+)?/)
        # 여기서는 예시로 빈 배열 반환
        []
      end

      def check_data_type_consistency(formula, context)
        # 데이터 타입 불일치 검사 로직
        []
      end

      def get_performance_alternative(function_name)
        alternatives = {
          "VLOOKUP" => "XLOOKUP이나 INDEX+MATCH 조합을 사용하세요.",
          "SUMPRODUCT" => "조건이 단순하면 SUMIFS를 사용하세요.",
          "OFFSET" => "가능하면 고정 범위 참조를 사용하세요.",
          "INDIRECT" => "직접 참조가 가능하면 INDIRECT를 피하세요."
        }
        alternatives[function_name] || "더 효율적인 대안을 고려하세요."
      end

      def estimate_function_calculation_time(function_name)
        # 함수별 예상 계산 시간 (ms)
        times = {
          "VLOOKUP" => 2.0,
          "SUMPRODUCT" => 5.0,
          "OFFSET" => 1.5,
          "INDIRECT" => 3.0
        }
        times[function_name] || 1.0
      end

      def analyze_range_complexity(formula)
        ranges = formula.scan(/[A-Z]+\d+:[A-Z]+\d+/)
        total_cells = ranges.sum do |range|
          # 범위 크기 계산 (단순화된 버전)
          parts = range.split(":")
          100 # 예시 값
        end

        {
          is_complex: total_cells > 10000,
          total_cells: total_cells,
          estimated_time: total_cells / 1000.0
        }
      end

      def analyze_function_nesting(formula)
        max_depth = calculate_max_nesting_depth(formula)
        {
          max_depth: max_depth,
          estimated_time: max_depth * 0.5
        }
      end

      def extract_functions(formula)
        formula.scan(/([A-Z][A-Z0-9\.]*)\s*\(/).flatten
      end

      def extract_references(formula)
        formula.scan(/[A-Z]+\d+(?::[A-Z]+\d+)?/)
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

      def convert_vlookup_to_xlookup(formula)
        # VLOOKUP을 XLOOKUP으로 변환하는 로직
        "XLOOKUP으로 변환된 수식 예시"
      end

      def find_hardcoded_values(formula)
        values = []

        # 숫자 리터럴
        values.concat(formula.scan(/\b\d+\.?\d*\b/))

        # 문자열 리터럴
        values.concat(formula.scan(/"[^"]*"/))

        values
      end

      def determine_value_type(value)
        case value
        when Numeric then "number"
        when String then "text"
        when TrueClass, FalseClass then "boolean"
        when Date, Time then "datetime"
        else "unknown"
        end
      end

      def measure_calculation_time(formula)
        start_time = Time.current
        @formula_engine_client.calculate_formula_with_session(formula)
        ((Time.current - start_time) * 1000).round(2)
      rescue
        0.0
      end

      def generate_formula_explanation(formula)
        "이 수식은 #{extract_functions(formula).join(', ')} 함수를 사용합니다."
      end

      def break_down_formula_steps(formula)
        steps = []
        functions = extract_functions(formula)

        functions.each_with_index do |func, index|
          steps << {
            step: index + 1,
            function: func,
            description: "#{func} 함수 실행"
          }
        end

        steps
      end

      def build_ai_formula_prompt(formula, context)
        <<~PROMPT
          다음 Excel 수식을 분석하고 더 나은 대안을 제안해주세요:

          수식: #{formula}
          셀 위치: #{context[:cell]}
          시트: #{context[:sheet]}

          다음 관점에서 개선안을 제시해주세요:
          1. 성능 최적화
          2. 가독성 향상
          3. 유지보수성 개선
          4. 오류 방지

          응답 형식을 JSON으로 제공하세요:
          {
            "alternatives": [
              {
                "formula": "개선된 수식",
                "explanation": "개선 이유",
                "performance_gain": "예상 성능 향상",
                "complexity_reduction": "복잡도 감소 정도"
              }
            ]
          }
        PROMPT
      end

      def parse_ai_formula_response(response)
        begin
          data = JSON.parse(response)
          data["alternatives"] || []
        rescue JSON::ParserError
          []
        end
      end
    end
  end
end
