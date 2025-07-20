# frozen_string_literal: true

# FormulaEngine 클라이언트 사용을 위한 헬퍼 메소드
# Rails 컨트롤러와 모델에서 쉽게 사용할 수 있는 인터페이스 제공
module FormulaEngineHelper
  extend ActiveSupport::Concern

  # === Excel 분석 통합 메소드 ===

  # Excel 파일 경로로부터 FormulaEngine 분석 수행
  def analyze_excel_file_with_formula_engine(file_path)
    return failure_result("파일 경로가 없습니다") unless file_path.present?
    return failure_result("파일이 존재하지 않습니다") unless File.exist?(file_path)

    begin
      # 1. 기존 FileAnalyzer로 Excel 데이터 추출
      file_analyzer = ExcelAnalysis::Services::FileAnalyzer.new(file_path)
      excel_data = file_analyzer.extract_data

      if excel_data[:error]
        return failure_result("Excel 파일 읽기 실패: #{excel_data[:error]}")
      end

      # 2. FormulaEngine용 데이터 변환
      formula_engine_data = convert_to_formula_engine_format(excel_data)

      # 3. FormulaEngine으로 고급 분석 수행
      formula_result = FormulaEngineClient.analyze_excel(formula_engine_data)

      if formula_result.failure?
        return failure_result("FormulaEngine 분석 실패: #{formula_result.error.message}")
      end

      # 4. 결과 통합
      combined_analysis = combine_analysis_results(excel_data, formula_result.value[:analysis])

      success_result(combined_analysis)

    rescue StandardError => e
      Rails.logger.error("Excel 분석 중 오류: #{e.message}")
      failure_result("Excel 분석 중 오류가 발생했습니다: #{e.message}")
    end
  end

  # Excel 파일 객체로부터 FormulaEngine 분석 수행
  def analyze_excel_file_object_with_formula_engine(excel_file)
    return failure_result("ExcelFile 객체가 없습니다") unless excel_file
    return failure_result("파일 경로가 없습니다") unless excel_file.file_path.present?

    analyze_excel_file_with_formula_engine(excel_file.file_path)
  end

  # === 수식 검증 및 계산 메소드 ===

  # 단일 수식 검증
  def validate_excel_formula(formula)
    return failure_result("수식이 없습니다") unless formula.present?

    begin
      result = FormulaEngineClient.validate_formula(formula)

      if result.success?
        validation_data = result.value

        {
          success: true,
          valid: validation_data[:valid],
          formula: validation_data[:formula],
          errors: validation_data[:errors] || [],
          message: validation_data[:valid] ? "수식이 유효합니다" : "수식에 오류가 있습니다"
        }
      else
        failure_result("수식 검증 실패: #{result.error.message}")
      end

    rescue StandardError => e
      Rails.logger.error("수식 검증 중 오류: #{e.message}")
      failure_result("수식 검증 중 오류가 발생했습니다: #{e.message}")
    end
  end

  # 단일 수식 계산
  def calculate_excel_formula(formula)
    return failure_result("수식이 없습니다") unless formula.present?

    begin
      result = FormulaEngineClient.calculate_formula(formula)

      if result.success?
        calculation_data = result.value

        {
          success: true,
          formula: calculation_data[:formula],
          result: calculation_data[:result],
          message: "수식 계산이 완료되었습니다"
        }
      else
        failure_result("수식 계산 실패: #{result.error.message}")
      end

    rescue StandardError => e
      Rails.logger.error("수식 계산 중 오류: #{e.message}")
      failure_result("수식 계산 중 오류가 발생했습니다: #{e.message}")
    end
  end

  # 여러 수식 일괄 검증
  def validate_multiple_formulas(formulas)
    return failure_result("수식 배열이 없습니다") unless formulas.is_a?(Array) && formulas.any?

    results = []

    formulas.each_with_index do |formula, index|
      if formula.present?
        validation = validate_excel_formula(formula)
        results << validation.merge(index: index, formula: formula)
      else
        results << {
          success: false,
          index: index,
          formula: formula,
          message: "빈 수식입니다"
        }
      end
    end

    valid_count = results.count { |r| r[:success] && r[:valid] }
    invalid_count = results.count { |r| !r[:success] || !r[:valid] }

    {
      success: true,
      total: formulas.count,
      valid: valid_count,
      invalid: invalid_count,
      results: results,
      message: "#{formulas.count}개 수식 중 #{valid_count}개 유효, #{invalid_count}개 무효"
    }
  end

  # === FormulaEngine 상태 확인 메소드 ===

  # FormulaEngine 헬스 체크
  def check_formula_engine_health
    begin
      result = FormulaEngineClient.health_check

      if result.success?
        health_data = result.value

        {
          success: true,
          status: health_data[:status],
          service: health_data[:service],
          version: health_data[:version],
          hyperformula_version: health_data[:hyperformula_version],
          supported_functions: health_data[:supported_functions],
          active_sessions: health_data[:active_sessions],
          uptime: health_data[:uptime],
          memory_usage: health_data[:memory],
          message: "FormulaEngine이 정상 작동 중입니다"
        }
      else
        failure_result("FormulaEngine 상태 확인 실패: #{result.error.message}")
      end

    rescue StandardError => e
      Rails.logger.error("FormulaEngine 헬스 체크 중 오류: #{e.message}")
      failure_result("FormulaEngine 연결 실패: #{e.message}")
    end
  end

  # FormulaEngine 지원 함수 목록 조회
  def get_formula_engine_functions
    begin
      result = FormulaEngineClient.supported_functions

      if result.success?
        functions_data = result.value

        {
          success: true,
          total: functions_data[:total],
          functions: functions_data[:functions],
          categories: functions_data[:categories],
          message: "#{functions_data[:total]}개의 Excel 함수를 지원합니다"
        }
      else
        failure_result("함수 목록 조회 실패: #{result.error.message}")
      end

    rescue StandardError => e
      Rails.logger.error("함수 목록 조회 중 오류: #{e.message}")
      failure_result("함수 목록 조회 중 오류가 발생했습니다: #{e.message}")
    end
  end

  # === 통계 및 분석 메소드 ===

  # Excel 파일의 수식 복잡도 분석
  def analyze_formula_complexity(file_path)
    analysis_result = analyze_excel_file_with_formula_engine(file_path)

    return analysis_result unless analysis_result[:success]

    analysis_data = analysis_result[:data]

    # 수식 복잡도 계산
    complexity_stats = calculate_formula_complexity_stats(analysis_data)

    {
      success: true,
      complexity: complexity_stats,
      recommendations: generate_complexity_recommendations(complexity_stats),
      message: "수식 복잡도 분석이 완료되었습니다"
    }
  end

  # Excel 파일의 함수 사용 통계
  def analyze_function_usage(file_path)
    analysis_result = analyze_excel_file_with_formula_engine(file_path)

    return analysis_result unless analysis_result[:success]

    analysis_data = analysis_result[:data]

    # 함수 사용 통계 계산
    function_stats = calculate_function_usage_stats(analysis_data)

    {
      success: true,
      function_usage: function_stats,
      insights: generate_function_insights(function_stats),
      message: "함수 사용 분석이 완료되었습니다"
    }
  end

  private

  # === 데이터 변환 메소드 ===

  # Excel 데이터를 FormulaEngine 형식으로 변환
  def convert_to_formula_engine_format(excel_data)
    return [] if excel_data[:error] || !excel_data[:worksheets]

    if excel_data[:worksheets].size == 1
      # 단일 시트: 2D 배열로 변환
      convert_worksheet_to_2d_array(excel_data[:worksheets].first)
    else
      # 다중 시트: sheets 객체로 변환
      sheets = {}
      excel_data[:worksheets].each do |worksheet|
        sheets[worksheet[:name]] = convert_worksheet_to_2d_array(worksheet)
      end
      { sheets: sheets }
    end
  end

  # 워크시트 데이터를 2D 배열로 변환
  def convert_worksheet_to_2d_array(worksheet)
    return [] unless worksheet[:data]

    max_row = worksheet[:row_count] || 0
    max_col = worksheet[:column_count] || 0

    # 2D 배열 초기화
    grid = Array.new(max_row) { Array.new(max_col) }

    # 데이터 채우기
    worksheet[:data].each_with_index do |row_data, row_index|
      row_data.each do |cell_data|
        row = cell_data[:row] || row_index
        col = cell_data[:col] || 0

        # 수식이 있으면 수식을, 없으면 값을 사용
        grid[row][col] = cell_data[:formula] || cell_data[:value]
      end
    end

    grid
  end

  # === 분석 결과 통합 메소드 ===

  # 기존 분석과 FormulaEngine 분석 결과 통합
  def combine_analysis_results(excel_data, formula_analysis)
    {
      basic_analysis: {
        format: excel_data[:format],
        worksheet_count: excel_data[:worksheets]&.size || 0,
        total_formulas: excel_data[:worksheets]&.sum { |ws| ws[:formula_count] || 0 } || 0,
        metadata: excel_data[:metadata]
      },
      advanced_analysis: formula_analysis,
      combined_insights: generate_combined_insights(excel_data, formula_analysis)
    }
  end

  # 통합 인사이트 생성
  def generate_combined_insights(excel_data, formula_analysis)
    insights = []

    # 수식 밀도 계산
    total_cells = excel_data[:worksheets]&.sum { |ws| (ws[:row_count] || 0) * (ws[:column_count] || 0) } || 0
    total_formulas = formula_analysis["totalFormulas"] || 0

    if total_cells > 0
      formula_density = (total_formulas.to_f / total_cells * 100).round(2)
      insights << {
        type: "formula_density",
        message: "수식 밀도: #{formula_density}% (전체 셀 중 #{total_formulas}개가 수식)",
        severity: formula_density > 50 ? "high" : formula_density > 20 ? "medium" : "low"
      }
    end

    # 함수 다양성 분석
    if formula_analysis["functions"]
      function_count = formula_analysis["functions"].keys.size
      insights << {
        type: "function_diversity",
        message: "#{function_count}가지 서로 다른 Excel 함수가 사용됨",
        severity: function_count > 20 ? "high" : function_count > 10 ? "medium" : "low"
      }
    end

    # 에러 분석
    if formula_analysis["errors"]&.any?
      error_count = formula_analysis["errors"].size
      insights << {
        type: "errors",
        message: "#{error_count}개의 수식 오류 발견",
        severity: "high"
      }
    end

    insights
  end

  # === 통계 계산 메소드 ===

  # 수식 복잡도 통계 계산
  def calculate_formula_complexity_stats(analysis_data)
    formula_analysis = analysis_data[:advanced_analysis]
    return {} unless formula_analysis

    {
      total_formulas: formula_analysis["totalFormulas"] || 0,
      complexity_distribution: formula_analysis["formulaComplexity"] || {},
      average_dependencies: calculate_average_dependencies(formula_analysis),
      max_dependencies: calculate_max_dependencies(formula_analysis)
    }
  end

  # 평균 의존성 계산
  def calculate_average_dependencies(formula_analysis)
    dependencies = formula_analysis["dependencies"] || []
    return 0 if dependencies.empty?

    total_deps = dependencies.sum { |dep| dep["dependsOn"] || 0 }
    (total_deps.to_f / dependencies.size).round(2)
  end

  # 최대 의존성 계산
  def calculate_max_dependencies(formula_analysis)
    dependencies = formula_analysis["dependencies"] || []
    dependencies.map { |dep| dep["dependsOn"] || 0 }.max || 0
  end

  # 함수 사용 통계 계산
  def calculate_function_usage_stats(analysis_data)
    formula_analysis = analysis_data[:advanced_analysis]
    return {} unless formula_analysis

    functions = formula_analysis["functions"] || {}
    total_usage = functions.values.sum

    {
      total_functions: functions.keys.size,
      total_usage: total_usage,
      most_used: functions.max_by { |_, count| count },
      usage_distribution: functions.sort_by { |_, count| -count }.first(10)
    }
  end

  # === 추천 사항 생성 메소드 ===

  # 복잡도 기반 추천 사항 생성
  def generate_complexity_recommendations(complexity_stats)
    recommendations = []

    if complexity_stats[:total_formulas] > 1000
      recommendations << {
        type: "performance",
        message: "많은 수의 수식이 있습니다. 성능 최적화를 고려해보세요.",
        priority: "high"
      }
    end

    if complexity_stats[:max_dependencies] > 10
      recommendations << {
        type: "maintenance",
        message: "복잡한 의존성을 가진 수식이 있습니다. 단순화를 고려해보세요.",
        priority: "medium"
      }
    end

    recommendations
  end

  # 함수 사용 인사이트 생성
  def generate_function_insights(function_stats)
    insights = []

    if function_stats[:most_used]
      func_name, usage_count = function_stats[:most_used]
      insights << {
        type: "most_used_function",
        message: "가장 많이 사용된 함수: #{func_name} (#{usage_count}회)",
        severity: "info"
      }
    end

    if function_stats[:total_functions] > 30
      insights << {
        type: "function_diversity",
        message: "다양한 Excel 함수가 사용되어 고급 Excel 기능을 활용하고 있습니다.",
        severity: "positive"
      }
    end

    insights
  end

  # === 유틸리티 메소드 ===

  # 성공 결과 생성
  def success_result(data, message = "성공")
    {
      success: true,
      data: data,
      message: message
    }
  end

  # 실패 결과 생성
  def failure_result(message, error_code = nil)
    {
      success: false,
      message: message,
      error_code: error_code
    }
  end
end
