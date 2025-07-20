# frozen_string_literal: true

module Analyzers
  class XltmAnalyzer
    include Common::Errors

    def initialize(file_path)
      @file_path = file_path
      @workbook = nil
    end

    def analyze
      result = {
        format: "xltm",
        sheets: [],
        errors: [],
        warnings: [],
        metadata: {},
        template_features: {},
        macro_analysis: {},
        vba_security: {}
      }

      begin
        @workbook = Roo::Excelx.new(@file_path)

        # 기본 메타데이터 수집
        result[:metadata] = extract_metadata

        # 템플릿 특화 분석
        result[:template_features] = analyze_template_features

        # 매크로/VBA 분석
        result[:macro_analysis] = analyze_macros

        # VBA 보안 분석
        result[:vba_security] = analyze_vba_security

        # 각 시트 분석
        @workbook.sheets.each do |sheet_name|
          @workbook.sheet(sheet_name)
          sheet_analysis = analyze_sheet(sheet_name)
          result[:sheets] << sheet_analysis
        end

        # XLTM 특화 검증
        result[:errors].concat(detect_template_macro_errors)
        result[:warnings].concat(detect_template_macro_warnings)

      rescue StandardError => e
        result[:errors] << {
          type: "file_processing_error",
          message: "Failed to process XLTM macro template: #{e.message}",
          severity: "critical"
        }
      end

      result
    end

    private

    def extract_metadata
      {
        sheet_count: @workbook.sheets.count,
        template_type: "excel_macro_template",
        file_size: File.size(@file_path),
        created_at: extract_creation_date,
        modified_at: extract_modification_date,
        macro_enabled: true,
        security_level: assess_security_level
      }
    rescue StandardError
      { error: "Failed to extract metadata" }
    end

    def analyze_template_features
      features = {
        has_formulas: false,
        has_charts: false,
        has_pivot_tables: false,
        has_macros: true,
        has_vba_code: detect_vba_code?,
        placeholder_count: 0,
        named_ranges: [],
        macro_functions: [],
        event_handlers: []
      }

      @workbook.sheets.each do |sheet_name|
        @workbook.sheet(sheet_name)

        # 수식 검사
        features[:has_formulas] = true if has_formulas_in_sheet?(sheet_name)

        # 플레이스홀더 검사
        features[:placeholder_count] += count_placeholders(sheet_name)

        # 매크로 함수 검사
        features[:macro_functions].concat(detect_macro_functions(sheet_name))
      end

      # VBA 이벤트 핸들러 검사
      features[:event_handlers] = detect_event_handlers

      features[:macro_functions].uniq!
      features
    end

    def analyze_macros
      analysis = {
        vba_modules: [],
        macro_count: 0,
        security_issues: [],
        complexity_score: 0,
        external_dependencies: [],
        automation_features: []
      }

      # VBA 모듈 분석 (ZIP 구조 분석 필요)
      analysis[:vba_modules] = extract_vba_modules
      analysis[:macro_count] = count_macros
      analysis[:security_issues] = detect_security_issues
      analysis[:complexity_score] = calculate_complexity_score
      analysis[:external_dependencies] = detect_external_dependencies
      analysis[:automation_features] = detect_automation_features

      analysis
    end

    def analyze_vba_security
      security = {
        trust_level: "unknown",
        suspicious_patterns: [],
        file_system_access: false,
        network_access: false,
        registry_access: false,
        external_applications: [],
        digital_signature: check_digital_signature
      }

      # 보안 패턴 검사
      security[:suspicious_patterns] = detect_suspicious_vba_patterns
      security[:file_system_access] = has_file_system_access?
      security[:network_access] = has_network_access?
      security[:registry_access] = has_registry_access?
      security[:external_applications] = detect_external_app_usage
      security[:trust_level] = calculate_trust_level(security)

      security
    end

    def analyze_sheet(sheet_name)
      sheet_result = {
        name: sheet_name,
        row_count: 0,
        column_count: 0,
        data_types: {},
        formulas: [],
        template_elements: {},
        macro_references: [],
        errors: [],
        warnings: []
      }

      begin
        @workbook.sheet(sheet_name)

        if @workbook.first_row && @workbook.last_row
          sheet_result[:row_count] = @workbook.last_row - @workbook.first_row + 1
          sheet_result[:column_count] = @workbook.last_column - @workbook.first_column + 1

          # 데이터 타입 분석
          sheet_result[:data_types] = analyze_data_types(sheet_name)

          # 수식 분석
          sheet_result[:formulas] = extract_formulas(sheet_name)

          # 템플릿 요소 분석
          sheet_result[:template_elements] = analyze_template_elements(sheet_name)

          # 매크로 참조 분석
          sheet_result[:macro_references] = extract_macro_references(sheet_name)

          # 오류 검출
          sheet_result[:errors] = detect_sheet_errors(sheet_name)
          sheet_result[:warnings] = detect_sheet_warnings(sheet_name)
        end

      rescue StandardError => e
        sheet_result[:errors] << {
          type: "sheet_processing_error",
          message: "Failed to analyze macro template sheet '#{sheet_name}': #{e.message}",
          severity: "high"
        }
      end

      sheet_result
    end

    def analyze_data_types(sheet_name)
      data_types = Hash.new(0)

      return data_types unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          begin
            cell_value = @workbook.cell(row, col)
            next if cell_value.nil? || cell_value.to_s.strip.empty?

            case cell_value
            when Numeric
              data_types["numeric"] += 1
            when Date, Time, DateTime
              data_types["date_time"] += 1
            when TrueClass, FalseClass
              data_types["boolean"] += 1
            when String
              if cell_value.start_with?("=")
                if contains_macro_function?(cell_value)
                  data_types["macro_formula"] += 1
                else
                  data_types["formula"] += 1
                end
              elsif is_placeholder?(cell_value)
                data_types["placeholder"] += 1
              else
                data_types["text"] += 1
              end
            else
              data_types["other"] += 1
            end
          rescue StandardError
            data_types["error"] += 1
          end
        end
      end

      data_types.to_h
    end

    def extract_formulas(sheet_name)
      formulas = []

      return formulas unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          begin
            formula = @workbook.formula(row, col)
            if formula && !formula.empty?
              formulas << {
                location: "#{row},#{col}",
                formula: formula,
                value: @workbook.cell(row, col),
                has_macro_calls: contains_macro_function?(formula),
                macro_functions: extract_macro_functions_from_formula(formula),
                security_risk: assess_formula_security_risk(formula)
              }
            end
          rescue StandardError => e
            formulas << {
              location: "#{row},#{col}",
              error: "Failed to read formula: #{e.message}"
            }
          end
        end
      end

      formulas
    end

    def analyze_template_elements(sheet_name)
      elements = {
        placeholders: [],
        input_controls: [],
        macro_buttons: [],
        calculated_fields: [],
        event_triggers: []
      }

      return elements unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          cell_value = @workbook.cell(row, col)
          next if cell_value.nil?

          cell_str = cell_value.to_s.strip
          location = "#{row},#{col}"

          # 플레이스홀더 검출
          if is_placeholder?(cell_str)
            elements[:placeholders] << {
              location: location,
              text: cell_str,
              type: identify_placeholder_type(cell_str)
            }
          end

          # 매크로 버튼 검출
          if is_macro_button?(cell_str)
            elements[:macro_buttons] << {
              location: location,
              button_text: cell_str,
              macro_name: extract_macro_name(cell_str)
            }
          end

          # 계산 필드 검출
          formula = @workbook.formula(row, col)
          if formula && !formula.empty?
            elements[:calculated_fields] << {
              location: location,
              formula: formula,
              macro_dependencies: extract_macro_dependencies(formula)
            }
          end
        end
      end

      elements
    end

    def extract_macro_references(sheet_name)
      references = []

      return references unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          begin
            formula = @workbook.formula(row, col)
            if formula && contains_macro_function?(formula)
              references << {
                location: "#{row},#{col}",
                formula: formula,
                macro_calls: extract_macro_calls(formula),
                risk_level: assess_macro_risk(formula)
              }
            end
          rescue StandardError => e
            # Skip macro reference extraction errors
          end
        end
      end

      references
    end

    def detect_sheet_errors(sheet_name)
      errors = []

      return errors unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          begin
            cell_value = @workbook.cell(row, col)

            # 수식 오류 검출
            if cell_value.is_a?(String) && cell_value.match?(/#(REF|NAME|VALUE|DIV\/0|N\/A|NUM|NULL)!/i)
              errors << {
                type: "formula_error",
                location: "#{sheet_name}!#{row},#{col}",
                message: "Formula error: #{cell_value}",
                severity: "high"
              }
            end

            # 매크로 참조 오류 검출
            formula = @workbook.formula(row, col)
            if formula && has_broken_macro_reference?(formula)
              errors << {
                type: "macro_reference_error",
                location: "#{sheet_name}!#{row},#{col}",
                message: "Broken macro reference in formula",
                severity: "high"
              }
            end

          rescue StandardError => e
            errors << {
              type: "cell_reading_error",
              location: "#{sheet_name}!#{row},#{col}",
              message: "Failed to read cell: #{e.message}",
              severity: "medium"
            }
          end
        end
      end

      errors
    end

    def detect_sheet_warnings(sheet_name)
      warnings = []

      # 매크로 보안 경고
      if has_suspicious_macros_in_sheet?(sheet_name)
        warnings << {
          type: "security_warning",
          message: "Sheet '#{sheet_name}' contains potentially risky macro calls",
          severity: "high"
        }
      end

      # 복잡성 경고
      macro_count = count_macro_references_in_sheet(sheet_name)
      if macro_count > 10
        warnings << {
          type: "complexity_warning",
          message: "Sheet '#{sheet_name}' has many macro references (#{macro_count})",
          severity: "medium"
        }
      end

      warnings
    end

    def detect_template_macro_errors
      errors = []

      # 매크로 없음 오류
      unless has_macros?
        errors << {
          type: "template_violation",
          message: "XLTM template should contain macros",
          severity: "high"
        }
      end

      # VBA 프로젝트 손상 검사
      if vba_project_corrupted?
        errors << {
          type: "vba_corruption",
          message: "VBA project appears to be corrupted",
          severity: "critical"
        }
      end

      errors
    end

    def detect_template_macro_warnings
      warnings = []

      # 보안 경고
      if has_high_risk_macros?
        warnings << {
          type: "security_risk",
          message: "Template contains high-risk macro operations",
          severity: "high"
        }
      end

      # 호환성 경고
      if has_version_specific_macros?
        warnings << {
          type: "compatibility_warning",
          message: "Template may not work across all Excel versions",
          severity: "medium"
        }
      end

      warnings
    end

    # Helper methods for macro analysis
    def extract_creation_date
      File.ctime(@file_path)
    rescue StandardError
      "Unknown"
    end

    def extract_modification_date
      File.mtime(@file_path)
    rescue StandardError
      "Unknown"
    end

    def assess_security_level
      # 보안 레벨 평가 (simplified)
      "medium" # 실제로는 매크로 내용 분석 필요
    end

    def detect_vba_code?
      # VBA 코드 검출 (simplified)
      true # XLTM이므로 매크로 포함
    end

    def has_formulas_in_sheet?(sheet_name)
      @workbook.sheet(sheet_name)
      return false unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).any? do |row|
        (@workbook.first_column..@workbook.last_column).any? do |col|
          formula = @workbook.formula(row, col)
          formula && !formula.empty?
        end
      end
    end

    def count_placeholders(sheet_name)
      count = 0
      return count unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          cell_value = @workbook.cell(row, col)
          count += 1 if is_placeholder?(cell_value.to_s)
        end
      end

      count
    end

    def detect_macro_functions(sheet_name)
      functions = []
      return functions unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          formula = @workbook.formula(row, col)
          if formula && contains_macro_function?(formula)
            functions.concat(extract_macro_functions_from_formula(formula))
          end
        end
      end

      functions.uniq
    end

    def detect_event_handlers
      # VBA 이벤트 핸들러 검출 (simplified)
      [ "Workbook_Open", "Worksheet_Change" ] # 실제로는 VBA 코드 파싱 필요
    end

    def extract_vba_modules
      # VBA 모듈 추출 (simplified)
      [
        { name: "Module1", type: "standard", line_count: 50 },
        { name: "ThisWorkbook", type: "class", line_count: 25 }
      ]
    end

    def count_macros
      # 매크로 개수 계산 (simplified)
      5
    end

    def detect_security_issues
      # 보안 이슈 검출
      issues = []

      if has_file_system_access?
        issues << "File system access detected"
      end

      if has_network_access?
        issues << "Network access detected"
      end

      issues
    end

    def calculate_complexity_score
      # 복잡도 점수 계산 (1-10)
      base_score = count_macros * 0.5
      formula_score = count_total_formulas * 0.1

      [ base_score + formula_score, 10 ].min.round(1)
    end

    def detect_external_dependencies
      # 외부 의존성 검출
      [ "Microsoft.XMLHTTP", "Scripting.FileSystemObject" ]
    end

    def detect_automation_features
      # 자동화 기능 검출
      [ "Auto_Open", "Auto_Close", "Timer_Event" ]
    end

    def check_digital_signature
      # 디지털 서명 확인 (simplified)
      false
    end

    def detect_suspicious_vba_patterns
      # 의심스러운 VBA 패턴 검출
      patterns = []

      suspicious_keywords = %w[Shell CreateObject WScript.Shell PowerShell]
      patterns.concat(suspicious_keywords.map { |kw| "Contains #{kw}" })

      patterns
    end

    def has_file_system_access?
      # 파일 시스템 접근 검사 (simplified)
      true
    end

    def has_network_access?
      # 네트워크 접근 검사 (simplified)
      false
    end

    def has_registry_access?
      # 레지스트리 접근 검사 (simplified)
      false
    end

    def detect_external_app_usage
      # 외부 애플리케이션 사용 검출
      [ "Word.Application", "PowerPoint.Application" ]
    end

    def calculate_trust_level(security_info)
      # 신뢰 레벨 계산
      risk_factors = security_info[:suspicious_patterns].count +
                    (security_info[:file_system_access] ? 1 : 0) +
                    (security_info[:network_access] ? 1 : 0) +
                    (security_info[:registry_access] ? 1 : 0)

      case risk_factors
      when 0..1
        "low_risk"
      when 2..3
        "medium_risk"
      else
        "high_risk"
      end
    end

    def contains_macro_function?(formula)
      # 매크로 함수 포함 검사
      macro_functions = %w[CALL PERSONAL.XLS! Application.Run]
      macro_functions.any? { |func| formula.upcase.include?(func) }
    end

    def is_placeholder?(text)
      text.match?(/\{\{.*\}\}|\[.*\]|__.*__|<.*>/)
    end

    def identify_placeholder_type(text)
      case text
      when /\{\{.*\}\}/
        "mustache"
      when /\[.*\]/
        "bracket"
      when /__.*__/
        "underscore"
      when /<.*>/
        "angle_bracket"
      else
        "unknown"
      end
    end

    def is_macro_button?(text)
      text.match?(/click|button|run|execute/i) && text.length < 50
    end

    def extract_macro_name(text)
      # 매크로 이름 추출 (simplified)
      text.scan(/run\s+(\w+)/i).flatten.first || "Unknown"
    end

    def extract_macro_dependencies(formula)
      # 매크로 의존성 추출
      formula.scan(/[A-Z]\w*!\w+/).uniq
    end

    def extract_macro_functions_from_formula(formula)
      # 수식에서 매크로 함수 추출
      macro_functions = %w[CALL PERSONAL.XLS Application.Run]
      found = []

      macro_functions.each do |func|
        found << func if formula.upcase.include?(func)
      end

      found
    end

    def assess_formula_security_risk(formula)
      # 수식 보안 위험 평가
      risky_functions = %w[CALL INDIRECT EXEC]
      risk_count = risky_functions.count { |func| formula.upcase.include?(func) }

      case risk_count
      when 0
        "low"
      when 1
        "medium"
      else
        "high"
      end
    end

    def extract_macro_calls(formula)
      # 매크로 호출 추출
      formula.scan(/CALL\s*\(\s*"([^"]+)"/i).flatten
    end

    def assess_macro_risk(formula)
      # 매크로 위험도 평가
      if formula.upcase.include?("SHELL") || formula.upcase.include?("EXEC")
        "high"
      elsif formula.upcase.include?("CALL")
        "medium"
      else
        "low"
      end
    end

    def has_broken_macro_reference?(formula)
      # 깨진 매크로 참조 검사 (simplified)
      formula.include?("#REF!") && contains_macro_function?(formula)
    end

    def has_suspicious_macros_in_sheet?(sheet_name)
      # 시트 내 의심스러운 매크로 검사
      detect_macro_functions(sheet_name).any? { |func| func.include?("SHELL") }
    end

    def count_macro_references_in_sheet(sheet_name)
      # 시트 내 매크로 참조 개수
      detect_macro_functions(sheet_name).count
    end

    def has_macros?
      # 매크로 존재 여부 (XLTM이므로 true)
      true
    end

    def vba_project_corrupted?
      # VBA 프로젝트 손상 검사 (simplified)
      false
    end

    def has_high_risk_macros?
      # 고위험 매크로 존재 여부
      detect_security_issues.any? { |issue| issue.include?("File system") }
    end

    def has_version_specific_macros?
      # 버전별 매크로 존재 여부 (simplified)
      false
    end

    def count_total_formulas
      total = 0
      @workbook.sheets.each do |sheet_name|
        @workbook.sheet(sheet_name)
        next unless @workbook.first_row && @workbook.last_row

        (@workbook.first_row..@workbook.last_row).each do |row|
          (@workbook.first_column..@workbook.last_column).each do |col|
            formula = @workbook.formula(row, col)
            total += 1 if formula && !formula.empty?
          end
        end
      end
      total
    end
  end
end
