# frozen_string_literal: true

module Analyzers
  class XltAnalyzer
    include Common::Errors

    def initialize(file_path)
      @file_path = file_path
      @workbook = nil
    end

    def analyze
      result = {
        format: "xlt",
        sheets: [],
        errors: [],
        warnings: [],
        metadata: {},
        template_features: {},
        legacy_issues: []
      }

      begin
        @workbook = Roo::Excel.new(@file_path)

        # 기본 메타데이터 수집
        result[:metadata] = extract_metadata

        # 템플릿 특화 분석
        result[:template_features] = analyze_template_features

        # 각 시트 분석
        @workbook.sheets.each do |sheet_name|
          @workbook.sheet(sheet_name)
          sheet_analysis = analyze_sheet(sheet_name)
          result[:sheets] << sheet_analysis
        end

        # XLT 특화 검증
        result[:legacy_issues] = detect_legacy_issues
        result[:errors].concat(detect_template_errors)
        result[:warnings].concat(detect_template_warnings)

      rescue StandardError => e
        result[:errors] << {
          type: "file_processing_error",
          message: "Failed to process XLT legacy template: #{e.message}",
          severity: "critical"
        }
      end

      result
    end

    private

    def extract_metadata
      {
        sheet_count: @workbook.sheets.count,
        template_type: "excel_legacy_template",
        file_size: File.size(@file_path),
        excel_version: detect_excel_version,
        created_at: extract_creation_date,
        encoding: "Windows-1252" # 일반적인 XLT 인코딩
      }
    rescue StandardError
      { error: "Failed to extract metadata" }
    end

    def analyze_template_features
      features = {
        has_formulas: false,
        has_charts: false,
        has_pivot_tables: false,
        has_macros: detect_macros,
        placeholder_count: 0,
        named_ranges: [],
        legacy_functions: []
      }

      @workbook.sheets.each do |sheet_name|
        @workbook.sheet(sheet_name)

        # 수식 검사
        features[:has_formulas] = true if has_formulas_in_sheet?(sheet_name)

        # 플레이스홀더 검사
        features[:placeholder_count] += count_placeholders(sheet_name)

        # 레거시 함수 검사
        features[:legacy_functions].concat(detect_legacy_functions(sheet_name))
      end

      features[:legacy_functions].uniq!
      features
    end

    def analyze_sheet(sheet_name)
      sheet_result = {
        name: sheet_name,
        row_count: 0,
        column_count: 0,
        data_types: {},
        formulas: [],
        template_elements: {},
        legacy_features: {},
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

          # 레거시 기능 분석
          sheet_result[:legacy_features] = analyze_legacy_features(sheet_name)

          # 오류 검출
          sheet_result[:errors] = detect_sheet_errors(sheet_name)
          sheet_result[:warnings] = detect_sheet_warnings(sheet_name)
        end

      rescue StandardError => e
        sheet_result[:errors] << {
          type: "sheet_processing_error",
          message: "Failed to analyze legacy sheet '#{sheet_name}': #{e.message}",
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
                data_types["formula"] += 1
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
                legacy_compatibility: assess_legacy_compatibility(formula)
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
        headers: [],
        input_fields: [],
        calculated_fields: [],
        formatting_regions: []
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

          # 헤더 검출
          if is_likely_header?(cell_str, row)
            elements[:headers] << {
              location: location,
              text: cell_str
            }
          end

          # 계산 필드 검출
          formula = @workbook.formula(row, col)
          if formula && !formula.empty?
            elements[:calculated_fields] << {
              location: location,
              formula: formula,
              legacy_functions: extract_legacy_functions_from_formula(formula)
            }
          end
        end
      end

      elements
    end

    def analyze_legacy_features(sheet_name)
      features = {
        lotus_123_functions: [],
        excel_4_macros: [],
        old_date_formats: [],
        character_encoding_issues: []
      }

      return features unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          cell_value = @workbook.cell(row, col)
          formula = @workbook.formula(row, col)

          # Lotus 1-2-3 호환 함수 검출
          if formula && contains_lotus_functions?(formula)
            features[:lotus_123_functions] << {
              location: "#{row},#{col}",
              formula: formula
            }
          end

          # 인코딩 문제 검출
          if cell_value.is_a?(String) && has_encoding_issues?(cell_value)
            features[:character_encoding_issues] << {
              location: "#{row},#{col}",
              issue: "Non-UTF8 characters detected"
            }
          end
        end
      end

      features
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

            # 레거시 호환성 오류
            formula = @workbook.formula(row, col)
            if formula && has_compatibility_issues?(formula)
              errors << {
                type: "compatibility_error",
                location: "#{sheet_name}!#{row},#{col}",
                message: "Formula may not work in modern Excel versions",
                severity: "medium"
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

      # 인코딩 경고
      if has_non_ascii_content?(sheet_name)
        warnings << {
          type: "encoding_warning",
          message: "Sheet '#{sheet_name}' contains non-ASCII characters that may not display correctly",
          severity: "medium"
        }
      end

      # 레거시 함수 경고
      legacy_functions = detect_legacy_functions(sheet_name)
      if legacy_functions.any?
        warnings << {
          type: "legacy_functions",
          message: "Sheet contains legacy functions: #{legacy_functions.join(', ')}",
          severity: "low"
        }
      end

      warnings
    end

    def detect_legacy_issues
      issues = []

      # Excel 버전 호환성
      excel_version = detect_excel_version
      if excel_version && excel_version < 12 # Excel 2007 이전
        issues << {
          type: "version_compatibility",
          message: "Created with Excel #{excel_version}, may have compatibility issues with modern versions",
          severity: "medium"
        }
      end

      # 파일 크기 제한
      if File.size(@file_path) > 65536 * 256 # 구 Excel 한계
        issues << {
          type: "size_limitation",
          message: "File may exceed legacy Excel size limitations",
          severity: "low"
        }
      end

      issues
    end

    def detect_template_errors
      errors = []

      # 템플릿 구조 검증
      if @workbook.sheets.empty?
        errors << {
          type: "structure_error",
          message: "XLT template contains no sheets",
          severity: "critical"
        }
      end

      # 매크로 바이러스 스캔 (simplified)
      if potentially_malicious_macros?
        errors << {
          type: "security_warning",
          message: "Template may contain potentially harmful macros",
          severity: "high"
        }
      end

      errors
    end

    def detect_template_warnings
      warnings = []

      # 복잡성 경고
      if count_total_formulas > 50
        warnings << {
          type: "complexity_warning",
          message: "Legacy template contains many formulas, consider modernization",
          severity: "medium"
        }
      end

      warnings
    end

    # Helper methods
    def detect_excel_version
      # XLT 파일에서 Excel 버전 추출 (simplified)
      case File.size(@file_path)
      when 0..65536
        "4.0"
      when 65537..1048576
        "95-2003"
      else
        "unknown"
      end
    end

    def extract_creation_date
      File.ctime(@file_path)
    rescue StandardError
      "Unknown"
    end

    def detect_macros
      # XLT 파일에서 매크로 검출 (simplified)
      false # 실제로는 OLE 구조 분석이 필요
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

    def detect_legacy_functions(sheet_name)
      functions = []
      return functions unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          formula = @workbook.formula(row, col)
          next unless formula

          # 레거시 함수 패턴 검출
          legacy_patterns = %w[CALL REGISTER EVALUATE SQL.REQUEST]
          legacy_patterns.each do |pattern|
            functions << pattern if formula.upcase.include?(pattern)
          end
        end
      end

      functions.uniq
    end

    def is_placeholder?(text)
      text.match?(/\{\{.*\}\}|\[.*\]|__.*__|<.*>|&.*&/)
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
      when /&.*&/
        "ampersand"
      else
        "legacy_pattern"
      end
    end

    def is_likely_header?(text, row)
      # 첫 번째 행이거나 대문자로 시작하는 짧은 텍스트
      row <= 3 && text.length < 50 && text.match?(/^[A-Z]/)
    end

    def extract_legacy_functions_from_formula(formula)
      legacy_functions = %w[CALL REGISTER EVALUATE SQL.REQUEST DIRECTORY DOCUMENTS]
      found = []

      legacy_functions.each do |func|
        found << func if formula.upcase.include?(func)
      end

      found
    end

    def assess_legacy_compatibility(formula)
      issues = []

      # 구 함수명 검사
      if formula.match?(/CALL|REGISTER|EVALUATE/i)
        issues << "Contains legacy macro functions"
      end

      # 날짜 시스템 검사
      if formula.match?(/DATE|NOW|TODAY/i)
        issues << "May have 1900/1904 date system issues"
      end

      issues.empty? ? "compatible" : issues.join("; ")
    end

    def contains_lotus_functions?(formula)
      lotus_functions = %w[@SUM @IF @VLOOKUP @COUNT]
      lotus_functions.any? { |func| formula.include?(func) }
    end

    def has_encoding_issues?(text)
      # 인코딩 문제 검출 (simplified)
      !text.valid_encoding? || text.bytes.any? { |b| b > 127 && b < 160 }
    rescue StandardError
      false
    end

    def has_compatibility_issues?(formula)
      # 호환성 문제가 있는 함수들
      problematic_functions = %w[CALL REGISTER EVALUATE SQL.REQUEST]
      problematic_functions.any? { |func| formula.upcase.include?(func) }
    end

    def has_non_ascii_content?(sheet_name)
      @workbook.sheet(sheet_name)
      return false unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).any? do |row|
        (@workbook.first_column..@workbook.last_column).any? do |col|
          cell_value = @workbook.cell(row, col)
          cell_value.is_a?(String) && cell_value.match?(/[^\x00-\x7F]/)
        end
      end
    end

    def potentially_malicious_macros?
      # 매크로 악성코드 패턴 검출 (simplified)
      false # 실제로는 VBA 코드 분석이 필요
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
