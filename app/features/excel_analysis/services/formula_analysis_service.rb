# frozen_string_literal: true

module ExcelAnalysis
  module Services
    class FormulaAnalysisService
      include ActiveModel::Model

      # FormulaEngine 분석 오류
      class AnalysisError < StandardError; end
      class DataExtractionError < StandardError; end

      attr_reader :excel_file, :file_analyzer_data

      def initialize(excel_file)
        @excel_file = excel_file
        @file_analyzer_data = nil
        @formula_engine_client = FormulaEngineClient.instance
      end

      # Excel 파일의 수식 분석 수행
      def analyze
        Rails.logger.info("FormulaEngine 분석 시작: #{excel_file.id}")

        # 1. Excel 데이터 추출
        extract_result = extract_excel_data
        return extract_result if extract_result.failure?

        # 2. FormulaEngine으로 분석
        analysis_result = perform_formula_analysis(extract_result.value)
        return analysis_result if analysis_result.failure?

        # 3. 분석 결과 처리
        process_analysis_result(analysis_result.value)

      rescue StandardError => e
        Rails.logger.error("FormulaEngine 분석 실패: #{e.message}")
        Common::Result.failure(
          Common::Errors::BusinessError.new(
            message: "수식 분석 실패: #{e.message}",
            code: "FORMULA_ANALYSIS_ERROR",
            details: { excel_file_id: excel_file.id }
          )
        )
      end

      private

      # Excel 데이터 추출
      def extract_excel_data
        analyzer = FileAnalyzer.new(excel_file.file_path)
        @file_analyzer_data = analyzer.extract_data

        if @file_analyzer_data[:error]
          return Common::Result.failure(
            Common::Errors::FileProcessingError.new(
              message: "Excel 데이터 추출 실패: #{@file_analyzer_data[:error]}",
              details: { file_path: excel_file.file_path }
            )
          )
        end

        # FormulaEngine 형식으로 데이터 변환
        excel_data = convert_to_formula_engine_format(@file_analyzer_data)

        Common::Result.success(excel_data)
      end

      # FileAnalyzer 데이터를 FormulaEngine 형식으로 변환
      def convert_to_formula_engine_format(analyzer_data)
        {
          format: analyzer_data[:format],
          worksheets: analyzer_data[:worksheets]&.map do |worksheet|
            {
              name: worksheet[:name],
              data: worksheet[:data] || [],
              formulas: worksheet[:formulas] || [],
              dimensions: {
                rows: worksheet[:row_count] || 0,
                columns: worksheet[:column_count] || 0
              }
            }
          end || [],
          metadata: analyzer_data[:metadata] || {}
        }
      end

      # FormulaEngine 분석 수행
      def perform_formula_analysis(excel_data)
        @formula_engine_client.analyze_excel_with_session(excel_data)
      end

      # 분석 결과 처리 및 구조화
      def process_analysis_result(raw_analysis)
        analysis_data = raw_analysis[:analysis] || {}

        processed_result = {
          formula_analysis: analysis_data,
          formula_complexity_score: calculate_complexity_score(analysis_data),
          formula_count: extract_formula_count(analysis_data),
          formula_functions: extract_function_statistics(analysis_data),
          formula_dependencies: extract_dependencies(analysis_data),
          circular_references: extract_circular_references(analysis_data),
          formula_errors: extract_formula_errors(analysis_data),
          formula_optimization_suggestions: generate_optimization_suggestions(analysis_data)
        }

        Rails.logger.info("FormulaEngine 분석 완료: #{excel_file.id}, 수식 #{processed_result[:formula_count]}개")

        Common::Result.success(processed_result)
      end

      # 복잡도 점수 계산
      def calculate_complexity_score(analysis_data)
        return 0.0 unless analysis_data.present?

        base_score = 0.0

        # 수식 개수에 따른 기본 점수
        formula_count = analysis_data.dig("summary", "totalFormulas") || 0
        base_score += formula_count * 0.1

        # 함수 사용 복잡도
        functions = analysis_data.dig("functions", "details") || []
        complex_functions = functions.select { |f| is_complex_function?(f["name"]) }
        base_score += complex_functions.size * 0.3

        # 중첩 수식 복잡도
        nested_formulas = analysis_data.dig("dependencies", "nested") || []
        base_score += nested_formulas.size * 0.5

        # 순환 참조
        circular_refs = analysis_data.dig("circularReferences") || []
        base_score += circular_refs.size * 1.0

        # 최대 5.0으로 제한
        [ base_score, 5.0 ].min.round(2)
      end

      # 복잡한 함수인지 판별
      def is_complex_function?(function_name)
        complex_functions = %w[
          VLOOKUP HLOOKUP INDEX MATCH SUMIFS COUNTIFS AVERAGEIFS
          INDIRECT OFFSET CHOOSE IFERROR IFNA SUMPRODUCT
          ARRAY LAMBDA LET XLOOKUP XMATCH FILTER SORT UNIQUE
        ]
        complex_functions.include?(function_name.upcase)
      end

      # 수식 개수 추출
      def extract_formula_count(analysis_data)
        return 0 unless analysis_data.present?

        # 전체 수식 개수
        total_formulas = analysis_data.dig("summary", "totalFormulas") || 0

        # FileAnalyzer 데이터에서도 확인
        if @file_analyzer_data
          file_formula_count = @file_analyzer_data[:worksheets]&.sum { |ws| ws[:formula_count] || 0 } || 0
          return [ total_formulas, file_formula_count ].max
        end

        total_formulas
      end

      # 함수 사용 통계 추출
      def extract_function_statistics(analysis_data)
        return {} unless analysis_data.present?

        functions_data = analysis_data.dig("functions") || {}

        {
          total_functions: functions_data.dig("summary", "totalFunctions") || 0,
          unique_functions: functions_data.dig("summary", "uniqueFunctions") || 0,
          function_usage: functions_data.dig("details") || [],
          categories: group_functions_by_category(functions_data.dig("details") || [])
        }
      end

      # 함수를 카테고리별로 그룹화
      def group_functions_by_category(function_details)
        categories = {}

        function_details.each do |func|
          category = categorize_function(func["name"])
          categories[category] ||= { count: 0, functions: [] }
          categories[category][:count] += func["count"]
          categories[category][:functions] << func
        end

        categories
      end

      # 함수 카테고리 분류
      def categorize_function(function_name)
        case function_name.upcase
        when /^(SUM|AVERAGE|COUNT|MAX|MIN|MEDIAN|MODE)/ then "Statistical"
        when /^(IF|AND|OR|NOT|XOR)/ then "Logical"
        when /^(VLOOKUP|HLOOKUP|INDEX|MATCH|LOOKUP)/ then "Lookup"
        when /^(LEFT|RIGHT|MID|LEN|FIND|SEARCH|SUBSTITUTE)/ then "Text"
        when /^(DATE|TIME|YEAR|MONTH|DAY|NOW|TODAY)/ then "Date & Time"
        when /^(ABS|ROUND|INT|MOD|POWER|SQRT)/ then "Math"
        when /^(OFFSET|INDIRECT|CHOOSE|ADDRESS)/ then "Reference"
        else "Other"
        end
      end

      # 의존성 정보 추출
      def extract_dependencies(analysis_data)
        return {} unless analysis_data.present?

        dependencies_data = analysis_data.dig("dependencies") || {}

        {
          total_dependencies: dependencies_data.dig("summary", "totalDependencies") || 0,
          direct_dependencies: dependencies_data.dig("direct") || [],
          indirect_dependencies: dependencies_data.dig("indirect") || [],
          nested_formulas: dependencies_data.dig("nested") || [],
          dependency_chains: dependencies_data.dig("chains") || []
        }
      end

      # 순환 참조 추출
      def extract_circular_references(analysis_data)
        return [] unless analysis_data.present?

        circular_refs = analysis_data.dig("circularReferences") || []

        circular_refs.map do |ref|
          {
            cells: ref["cells"] || [],
            chain: ref["chain"] || [],
            severity: calculate_circular_reference_severity(ref),
            description: generate_circular_reference_description(ref)
          }
        end
      end

      # 순환 참조 심각도 계산
      def calculate_circular_reference_severity(circular_ref)
        chain_length = circular_ref["chain"]&.size || 0

        case chain_length
        when 0..2 then "Low"
        when 3..5 then "Medium"
        else "High"
        end
      end

      # 순환 참조 설명 생성
      def generate_circular_reference_description(circular_ref)
        cells = circular_ref["cells"] || []
        return "순환 참조가 감지되었습니다." if cells.empty?

        "#{cells.join(' → ')} 간에 순환 참조가 발생했습니다."
      end

      # 수식 오류 추출
      def extract_formula_errors(analysis_data)
        return [] unless analysis_data.present?

        errors = analysis_data.dig("errors") || []

        errors.map do |error|
          {
            cell: error["cell"],
            formula: error["formula"],
            error_type: error["type"],
            message: error["message"],
            severity: error["severity"] || "Medium",
            suggestion: generate_error_fix_suggestion(error)
          }
        end
      end

      # 오류 수정 제안 생성
      def generate_error_fix_suggestion(error)
        case error["type"]&.upcase
        when "REF" then "참조된 셀이나 범위가 삭제되었습니다. 참조를 수정하세요."
        when "NAME" then "인식되지 않는 함수명이나 이름이 사용되었습니다."
        when "VALUE" then "잘못된 데이터 타입이 사용되었습니다."
        when "DIV" then "0으로 나누기 오류입니다. 분모를 확인하세요."
        when "NUM" then "숫자 관련 오류입니다. 입력값을 확인하세요."
        else "수식을 검토하고 수정하세요."
        end
      end

      # 최적화 제안 생성
      def generate_optimization_suggestions(analysis_data)
        suggestions = []
        return suggestions unless analysis_data.present?

        # 복잡한 수식 최적화 제안
        complex_formulas = find_complex_formulas(analysis_data)
        complex_formulas.each do |formula|
          suggestions << {
            type: "complexity_reduction",
            cell: formula["cell"],
            current_formula: formula["formula"],
            issue: "복잡한 수식이 감지되었습니다.",
            suggestion: "수식을 여러 단계로 나누거나 더 간단한 함수를 사용하는 것을 고려하세요.",
            priority: "Medium"
          }
        end

        # VLOOKUP -> XLOOKUP 제안
        vlookup_usage = find_vlookup_usage(analysis_data)
        vlookup_usage.each do |vlookup|
          suggestions << {
            type: "function_upgrade",
            cell: vlookup["cell"],
            current_formula: vlookup["formula"],
            issue: "VLOOKUP 함수가 사용되었습니다.",
            suggestion: "더 강력하고 유연한 XLOOKUP 함수 사용을 고려하세요.",
            priority: "Low"
          }
        end

        # 하드코딩된 값 제안
        hardcoded_values = find_hardcoded_values(analysis_data)
        hardcoded_values.each do |hardcode|
          suggestions << {
            type: "maintainability",
            cell: hardcode["cell"],
            current_formula: hardcode["formula"],
            issue: "하드코딩된 값이 감지되었습니다.",
            suggestion: "셀 참조나 이름 정의를 사용하여 유지보수성을 향상시키세요.",
            priority: "Medium"
          }
        end

        suggestions
      end

      # 복잡한 수식 찾기
      def find_complex_formulas(analysis_data)
        formulas = analysis_data.dig("formulas") || []
        formulas.select { |f| f["complexity_score"] && f["complexity_score"] > 3.0 }
      end

      # VLOOKUP 사용 찾기
      def find_vlookup_usage(analysis_data)
        formulas = analysis_data.dig("formulas") || []
        formulas.select { |f| f["formula"]&.include?("VLOOKUP") }
      end

      # 하드코딩된 값 찾기
      def find_hardcoded_values(analysis_data)
        formulas = analysis_data.dig("formulas") || []
        formulas.select { |f| has_hardcoded_values?(f["formula"]) }
      end

      # 하드코딩된 값 여부 확인
      def has_hardcoded_values?(formula)
        return false unless formula

        # 간단한 하드코딩 패턴 감지 (숫자, 문자열 리터럴)
        formula.match?(/\b\d+(\.\d+)?\b|"[^"]*"/)
      end
    end
  end
end
