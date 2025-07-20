# frozen_string_literal: true

module Analyzers
  class XlsxAnalyzer
    include Common::Errors

    def initialize(file_path)
      @file_path = file_path
      @workbook = nil
    end

    def analyze
      result = {
        format: "xlsx",
        sheets: [],
        errors: [],
        warnings: [],
        metadata: {},
        features: {}
      }

      begin
        @workbook = Roo::Excelx.new(@file_path)

        # 기본 메타데이터 수집
        result[:metadata] = extract_metadata

        # XLSX 특화 기능 분석
        result[:features] = analyze_xlsx_features

        # 각 시트 분석
        @workbook.sheets.each do |sheet_name|
          @workbook.sheet(sheet_name)
          sheet_analysis = analyze_sheet(sheet_name)
          result[:sheets] << sheet_analysis
        end

        # XLSX 특화 검증
        result[:errors].concat(detect_xlsx_errors)
        result[:warnings].concat(detect_xlsx_warnings)

      rescue StandardError => e
        result[:errors] << {
          type: "file_processing_error",
          message: "Failed to process XLSX file: #{e.message}",
          severity: "critical"
        }
      end

      result
    end

    private

    def extract_metadata
      {
        sheet_count: @workbook.sheets.count,
        file_size: File.size(@file_path),
        created_at: extract_creation_date,
        modified_at: extract_modification_date,
        excel_version: "Excel 2007+",
        compression: "ZIP"
      }
    rescue StandardError
      { error: "Failed to extract metadata" }
    end

    def analyze_xlsx_features
      features = {
        has_formulas: false,
        has_charts: false,
        has_pivot_tables: false,
        has_macros: false,
        has_hyperlinks: false,
        formula_count: 0,
        unique_functions: Set.new
      }

      @workbook.sheets.each do |sheet_name|
        @workbook.sheet(sheet_name)

        # 수식 검사
        if has_formulas_in_sheet?(sheet_name)
          features[:has_formulas] = true
          features[:formula_count] += count_formulas_in_sheet(sheet_name)
          features[:unique_functions].merge(extract_functions_from_sheet(sheet_name))
        end

        # 하이퍼링크 검사
        features[:has_hyperlinks] = true if has_hyperlinks_in_sheet?(sheet_name)
      end

      features[:unique_functions] = features[:unique_functions].to_a
      features
    end

    def analyze_sheet(sheet_name)
      sheet_result = {
        name: sheet_name,
        row_count: 0,
        column_count: 0,
        data_types: {},
        formulas: [],
        hyperlinks: [],
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

          # 하이퍼링크 분석
          sheet_result[:hyperlinks] = extract_hyperlinks(sheet_name)

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
                functions: extract_functions_from_formula(formula),
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

    def extract_hyperlinks(sheet_name)
      hyperlinks = []

      return hyperlinks unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          begin
            cell_value = @workbook.cell(row, col)
            if cell_value.is_a?(String) && is_hyperlink?(cell_value)
              hyperlinks << {
                location: "#{row},#{col}",
                url: extract_url(cell_value),
                display_text: cell_value,
                type: classify_hyperlink(cell_value)
              }
            end
          rescue StandardError => e
            # Skip hyperlink extraction errors
          end
        end
      end

      hyperlinks
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

            # 순환 참조 검출
            formula = @workbook.formula(row, col)
            if formula && has_circular_reference?(formula, row, col)
              errors << {
                type: "circular_reference",
                location: "#{sheet_name}!#{row},#{col}",
                message: "Potential circular reference in formula",
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

      # 빈 시트 경고
      if @workbook.first_row && @workbook.last_row
        total_cells = (@workbook.last_row - @workbook.first_row + 1) *
                     (@workbook.last_column - @workbook.first_column + 1)
        empty_cells = count_empty_cells(sheet_name)

        if empty_cells > total_cells * 0.9
          warnings << {
            type: "data_quality",
            message: "Sheet '#{sheet_name}' appears mostly empty",
            severity: "low"
          }
        end
      end

      # 큰 범위 경고
      if @workbook.last_row && @workbook.last_row > 10000
        warnings << {
          type: "performance",
          message: "Sheet '#{sheet_name}' has many rows (#{@workbook.last_row}), may impact performance",
          severity: "medium"
        }
      end

      warnings
    end

    def detect_xlsx_errors
      errors = []

      # 파일 구조 검증
      if @workbook.sheets.empty?
        errors << {
          type: "structure_error",
          message: "XLSX file contains no sheets",
          severity: "critical"
        }
      end

      # 파일 크기 검증
      if File.size(@file_path) > 100.megabytes
        errors << {
          type: "size_warning",
          message: "Large XLSX file may have performance issues",
          severity: "low"
        }
      end

      errors
    end

    def detect_xlsx_warnings
      warnings = []

      # 복잡성 경고
      total_formulas = count_total_formulas
      if total_formulas > 1000
        warnings << {
          type: "complexity_warning",
          message: "File contains many formulas (#{total_formulas}), may impact performance",
          severity: "medium"
        }
      end

      warnings
    end

    # Helper methods
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

    def count_formulas_in_sheet(sheet_name)
      count = 0
      return count unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          formula = @workbook.formula(row, col)
          count += 1 if formula && !formula.empty?
        end
      end

      count
    end

    def extract_functions_from_sheet(sheet_name)
      functions = Set.new
      return functions unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          formula = @workbook.formula(row, col)
          if formula && !formula.empty?
            functions.merge(extract_functions_from_formula(formula))
          end
        end
      end

      functions
    end

    def extract_functions_from_formula(formula)
      # Excel 함수 추출 (대문자 함수명 + 괄호)
      formula.scan(/[A-Z][A-Z0-9]*(?=\()/).uniq
    end

    def assess_formula_complexity(formula)
      # 수식 복잡도 평가
      function_count = formula.scan(/[A-Z]+\(/).count
      nesting_level = formula.count("(") - formula.count(")")

      case
      when function_count <= 1 && nesting_level <= 1
        "simple"
      when function_count <= 3 && nesting_level <= 2
        "medium"
      else
        "complex"
      end
    end

    def has_hyperlinks_in_sheet?(sheet_name)
      @workbook.sheet(sheet_name)
      return false unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).any? do |row|
        (@workbook.first_column..@workbook.last_column).any? do |col|
          cell_value = @workbook.cell(row, col)
          cell_value.is_a?(String) && is_hyperlink?(cell_value)
        end
      end
    end

    def is_hyperlink?(text)
      text.match?(/^https?:\/\/|^ftp:\/\/|^mailto:/)
    end

    def extract_url(text)
      # URL 추출 로직
      text.match(/(https?:\/\/[^\s]+|ftp:\/\/[^\s]+|mailto:[^\s]+)/)&.[](1) || text
    end

    def classify_hyperlink(text)
      case text
      when /^https?:\/\//
        "web"
      when /^ftp:\/\//
        "ftp"
      when /^mailto:/
        "email"
      else
        "other"
      end
    end

    def has_circular_reference?(formula, current_row, current_col)
      # 순환 참조 검출 (simplified)
      current_cell = "#{current_row},#{current_col}"
      formula.include?(current_cell)
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

    def count_total_formulas
      total = 0
      @workbook.sheets.each do |sheet_name|
        total += count_formulas_in_sheet(sheet_name)
      end
      total
    end
  end
end
