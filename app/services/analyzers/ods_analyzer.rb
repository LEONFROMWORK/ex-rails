# frozen_string_literal: true

module Analyzers
  class OdsAnalyzer
    include Common::Errors

    def initialize(file_path)
      @file_path = file_path
      @workbook = nil
    end

    def analyze
      result = {
        format: "ods",
        sheets: [],
        errors: [],
        warnings: [],
        metadata: {},
        compatibility_issues: []
      }

      begin
        @workbook = Roo::OpenOffice.new(@file_path)

        # 기본 메타데이터 수집
        result[:metadata] = extract_metadata

        # 각 시트 분석
        @workbook.sheets.each do |sheet_name|
          @workbook.sheet(sheet_name)
          sheet_analysis = analyze_sheet(sheet_name)
          result[:sheets] << sheet_analysis
        end

        # ODS 특화 검증
        result[:compatibility_issues] = check_libreoffice_compatibility
        result[:errors].concat(detect_ods_specific_errors)
        result[:warnings].concat(detect_ods_warnings)

      rescue StandardError => e
        result[:errors] << {
          type: "file_processing_error",
          message: "Failed to process ODS file: #{e.message}",
          severity: "critical"
        }
      end

      result
    end

    private

    def extract_metadata
      {
        sheet_count: @workbook.sheets.count,
        created_at: @workbook.info&.dig("created") || "Unknown",
        modified_at: @workbook.info&.dig("modified") || "Unknown",
        generator: @workbook.info&.dig("generator") || "Unknown",
        file_size: File.size(@file_path),
        encoding: "UTF-8"
      }
    rescue StandardError
      { error: "Failed to extract metadata" }
    end

    def analyze_sheet(sheet_name)
      sheet_result = {
        name: sheet_name,
        row_count: 0,
        column_count: 0,
        data_types: {},
        formulas: [],
        errors: [],
        warnings: []
      }

      begin
        @workbook.sheet(sheet_name)

        # 데이터 범위 계산
        if @workbook.first_row && @workbook.last_row
          sheet_result[:row_count] = @workbook.last_row - @workbook.first_row + 1
          sheet_result[:column_count] = @workbook.last_column - @workbook.first_column + 1

          # 데이터 타입 분석
          sheet_result[:data_types] = analyze_data_types(sheet_name)

          # 수식 분석
          sheet_result[:formulas] = extract_formulas(sheet_name)

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
                value: @workbook.cell(row, col)
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

            # LibreOffice 특화 함수 검출
            formula = @workbook.formula(row, col)
            if formula && contains_libreoffice_specific_functions?(formula)
              errors << {
                type: "compatibility_warning",
                location: "#{sheet_name}!#{row},#{col}",
                message: "Contains LibreOffice-specific functions that may not work in Excel",
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

      # 빈 행/열 검출
      if @workbook.first_row && @workbook.last_row
        empty_rows = count_empty_rows(sheet_name)
        if empty_rows > (@workbook.last_row - @workbook.first_row + 1) * 0.3
          warnings << {
            type: "data_quality",
            message: "Sheet '#{sheet_name}' has many empty rows (#{empty_rows})",
            severity: "low"
          }
        end
      end

      warnings
    end

    def check_libreoffice_compatibility
      issues = []

      # ODS 특화 기능 사용 검사
      @workbook.sheets.each do |sheet_name|
        @workbook.sheet(sheet_name)

        # 조건부 서식 검사 (ODS와 Excel 간 차이)
        if has_conditional_formatting?(sheet_name)
          issues << {
            type: "conditional_formatting",
            sheet: sheet_name,
            message: "Conditional formatting may not convert properly to Excel format"
          }
        end

        # 차트 호환성 검사
        if has_charts?(sheet_name)
          issues << {
            type: "chart_compatibility",
            sheet: sheet_name,
            message: "Charts may require adjustment when converting to Excel"
          }
        end
      end

      issues
    end

    def detect_ods_specific_errors
      errors = []

      # 파일 구조 검증
      begin
        if @workbook.sheets.empty?
          errors << {
            type: "structure_error",
            message: "ODS file contains no sheets",
            severity: "critical"
          }
        end

        # 대용량 파일 성능 경고
        if File.size(@file_path) > 10.megabytes
          errors << {
            type: "performance_warning",
            message: "Large ODS file may have slower processing",
            severity: "low"
          }
        end

      rescue StandardError => e
        errors << {
          type: "validation_error",
          message: "ODS validation failed: #{e.message}",
          severity: "high"
        }
      end

      errors
    end

    def detect_ods_warnings
      warnings = []

      # 인코딩 검사
      @workbook.sheets.each do |sheet_name|
        if contains_special_characters?(sheet_name)
          warnings << {
            type: "encoding_warning",
            sheet: sheet_name,
            message: "Sheet contains special characters that may not display correctly in all applications"
          }
        end
      end

      warnings
    end

    # Helper methods
    def contains_libreoffice_specific_functions?(formula)
      libreoffice_functions = %w[REGEX CURRENT BASE DECIMAL]
      libreoffice_functions.any? { |func| formula.upcase.include?(func) }
    end

    def count_empty_rows(sheet_name)
      empty_count = 0
      return empty_count unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        row_empty = true
        (@workbook.first_column..@workbook.last_column).each do |col|
          cell_value = @workbook.cell(row, col)
          if cell_value && !cell_value.to_s.strip.empty?
            row_empty = false
            break
          end
        end
        empty_count += 1 if row_empty
      end

      empty_count
    end

    def has_conditional_formatting?(sheet_name)
      # ODS 조건부 서식 검출 로직 (simplified)
      false # 실제 구현에서는 XML 파싱이 필요
    end

    def has_charts?(sheet_name)
      # ODS 차트 검출 로직 (simplified)
      false # 실제 구현에서는 XML 파싱이 필요
    end

    def contains_special_characters?(sheet_name)
      @workbook.sheet(sheet_name)
      return false unless @workbook.first_row && @workbook.last_row

      (@workbook.first_row..@workbook.last_row).each do |row|
        (@workbook.first_column..@workbook.last_column).each do |col|
          cell_value = @workbook.cell(row, col)
          if cell_value.is_a?(String) && cell_value.match?(/[^\x00-\x7F]/)
            return true
          end
        end
      end

      false
    end
  end
end
