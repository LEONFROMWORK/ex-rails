# frozen_string_literal: true

module Analyzers
  class XltxAnalyzer
    include Common::Errors

    def initialize(file_path)
      @file_path = file_path
      @workbook = nil
    end

    def analyze
      result = {
        format: "xltx",
        sheets: [],
        errors: [],
        warnings: [],
        metadata: {},
        template_features: {}
      }

      begin
        @workbook = Roo::Excelx.new(@file_path)

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

        # XLTX 특화 검증
        result[:errors].concat(detect_template_errors)
        result[:warnings].concat(detect_template_warnings)

      rescue StandardError => e
        result[:errors] << {
          type: "file_processing_error",
          message: "Failed to process XLTX template: #{e.message}",
          severity: "critical"
        }
      end

      result
    end

    private

    def extract_metadata
      {
        sheet_count: @workbook.sheets.count,
        template_type: "excel_template",
        file_size: File.size(@file_path),
        created_at: extract_creation_date,
        modified_at: extract_modification_date
      }
    rescue StandardError
      { error: "Failed to extract metadata" }
    end

    def analyze_template_features
      features = {
        has_formulas: false,
        has_charts: false,
        has_pivot_tables: false,
        has_macros: false,
        placeholder_count: 0,
        named_ranges: []
      }

      @workbook.sheets.each do |sheet_name|
        @workbook.sheet(sheet_name)

        # 수식 검사
        features[:has_formulas] = true if has_formulas_in_sheet?(sheet_name)

        # 플레이스홀더 검사 (일반적인 템플릿 패턴)
        features[:placeholder_count] += count_placeholders(sheet_name)

        # 명명된 범위 검사
        features[:named_ranges].concat(extract_named_ranges(sheet_name))
      end

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

          # 오류 검출
          sheet_result[:errors] = detect_sheet_errors(sheet_name)
          sheet_result[:warnings] = detect_sheet_warnings(sheet_name)
        end

      rescue StandardError => e
        sheet_result[:errors] << {
          type: "sheet_processing_error",
          message: "Failed to analyze sheet '#{sheet_name}': #{e.message}",
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
                complexity: assess_formula_complexity(formula)
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
        calculated_fields: []
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

          # 헤더 검출 (첫 번째 행이나 굵은 텍스트)
          if row == @workbook.first_row && !cell_str.empty?
            elements[:headers] << {
              location: location,
              text: cell_str
            }
          end

          # 입력 필드 검출 (빈 셀이나 특정 패턴)
          if is_input_field?(cell_str, row, col)
            elements[:input_fields] << {
              location: location,
              expected_type: infer_input_type(cell_str)
            }
          end

          # 계산 필드 검출
          formula = @workbook.formula(row, col)
          if formula && !formula.empty?
            elements[:calculated_fields] << {
              location: location,
              formula: formula,
              dependencies: extract_formula_dependencies(formula)
            }
          end
        end
      end

      elements
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

            # 템플릿 일관성 검사
            if is_broken_placeholder?(cell_value)
              errors << {
                type: "template_error",
                location: "#{sheet_name}!#{row},#{col}",
                message: "Malformed placeholder: #{cell_value}",
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

      # 빈 템플릿 경고
      if @workbook.first_row && @workbook.last_row
        total_cells = (@workbook.last_row - @workbook.first_row + 1) *
                     (@workbook.last_column - @workbook.first_column + 1)
        empty_cells = count_empty_cells(sheet_name)

        if empty_cells > total_cells * 0.8
          warnings << {
            type: "template_usage",
            message: "Sheet '#{sheet_name}' appears mostly empty for a template",
            severity: "low"
          }
        end
      end

      warnings
    end

    def detect_template_errors
      errors = []

      # 템플릿 파일 구조 검증
      if @workbook.sheets.empty?
        errors << {
          type: "structure_error",
          message: "XLTX template contains no sheets",
          severity: "critical"
        }
      end

      # 매크로 검출 (XLTX는 매크로를 포함하면 안됨)
      if contains_macros?
        errors << {
          type: "template_violation",
          message: "XLTX template should not contain macros (use XLTM instead)",
          severity: "high"
        }
      end

      errors
    end

    def detect_template_warnings
      warnings = []

      # 복잡성 경고
      total_formulas = count_total_formulas
      if total_formulas > 100
        warnings << {
          type: "complexity_warning",
          message: "Template contains many formulas (#{total_formulas}), consider optimization",
          severity: "medium"
        }
      end

      warnings
    end

    # Helper methods
    def extract_creation_date
      # XLTX 파일의 생성일 추출 로직
      File.ctime(@file_path)
    rescue StandardError
      "Unknown"
    end

    def extract_modification_date
      File.mtime(@file_path)
    rescue StandardError
      "Unknown"
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

    def extract_named_ranges(sheet_name)
      # XLTX 명명된 범위 추출 (simplified)
      []
    end

    def is_placeholder?(text)
      # 일반적인 플레이스홀더 패턴 검출
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

    def is_input_field?(text, row, col)
      # 입력 필드 패턴 검출 로직
      text.empty? || text.match?(/enter|input|fill|replace/i)
    end

    def infer_input_type(text)
      case text.downcase
      when /date|time/
        "date"
      when /number|amount|quantity/
        "numeric"
      when /email/
        "email"
      else
        "text"
      end
    end

    def extract_formula_dependencies(formula)
      # 수식 의존성 추출 (simplified)
      formula.scan(/[A-Z]+\d+/).uniq
    end

    def assess_formula_complexity(formula)
      # 수식 복잡도 평가
      function_count = formula.scan(/[A-Z]+\(/).count
      case function_count
      when 0..1
        "simple"
      when 2..4
        "medium"
      else
        "complex"
      end
    end

    def is_broken_placeholder?(value)
      return false unless value.is_a?(String)

      # 불완전한 플레이스홀더 패턴 검출
      value.match?(/\{[^}]*$|^[^{]*\}|\[[^\]]*$|^[^\[]*\]/)
    end

    def count_empty_cells(sheet_name)
      empty_count = 0
      return empty_count unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          cell_value = @workbook.cell(row, col)
          empty_count += 1 if cell_value.nil? || cell_value.to_s.strip.empty?
        end
      end

      empty_count
    end

    def contains_macros?
      # XLTX 파일에서 매크로 검출 (simplified)
      false # 실제로는 ZIP 구조 분석이 필요
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
