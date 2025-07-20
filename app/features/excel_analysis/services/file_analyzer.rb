# frozen_string_literal: true

module ExcelAnalysis
  module Services
    class FileAnalyzer
    def initialize(file_path)
      @file_path = file_path
    end

    def extract_data
      case File.extname(@file_path).downcase
      when ".xlsx"
        extract_xlsx_data
      when ".xlsm"
        extract_xlsm_data
      when ".xls"
        extract_xls_data
      when ".xlsb"
        extract_xlsb_data
      when ".xltx"
        extract_xltx_data
      when ".xlt"
        extract_xlt_data
      when ".xltm"
        extract_xltm_data
      when ".ods"
        extract_ods_data
      when ".csv"
        extract_csv_data
      else
        raise "Unsupported file format: #{File.extname(@file_path)}"
      end
    end

    # FormulaEngine을 사용한 수식 분석 수행
    def analyze_with_formula_engine(excel_file)
      formula_service = FormulaAnalysisService.new(excel_file)
      formula_service.analyze
    end

    private

    def extract_xlsx_data
      workbook = RubyXL::Parser.parse(@file_path)

      {
        format: "xlsx",
        worksheets: workbook.worksheets.map { |ws| extract_worksheet_data(ws) },
        metadata: {
          created_at: workbook.created_time,
          modified_at: workbook.modified_time,
          application: workbook.application,
          worksheet_count: workbook.worksheets.count
        }
      }
    rescue => e
      Rails.logger.error("Excel file analysis failed: #{e.message}")
      { error: e.message, format: "xlsx" }
    end

    def extract_xls_data
      # Use roo gem for older Excel files
      spreadsheet = Roo::Excel.new(@file_path)

      {
        format: "xls",
        worksheets: spreadsheet.sheets.map { |sheet_name|
          spreadsheet.default_sheet = sheet_name
          extract_roo_worksheet_data(spreadsheet, sheet_name)
        },
        metadata: {
          worksheet_count: spreadsheet.sheets.count
        }
      }
    rescue => e
      Rails.logger.error("Excel file analysis failed: #{e.message}")
      { error: e.message, format: "xls" }
    end

    def extract_xlsm_data
      # XLSM (Excel macro-enabled workbook) - use same logic as XLSX but with macro detection
      analyzer = Analyzers::XlsxAnalyzer.new(@file_path)
      result = analyzer.analyze
      result[:format] = "xlsm"
      result[:has_macros] = true
      result
    rescue => e
      Rails.logger.error("XLSM file analysis failed: #{e.message}")
      { error: e.message, format: "xlsm" }
    end

    def extract_xlsb_data
      # XLSB (Excel binary workbook) - use specialized analyzer
      analyzer = Analyzers::XlsbAnalyzer.new(@file_path)
      analyzer.analyze
    rescue => e
      Rails.logger.error("XLSB file analysis failed: #{e.message}")
      { error: e.message, format: "xlsb" }
    end

    def extract_xltx_data
      # XLTX (Excel template) - use specialized analyzer
      analyzer = Analyzers::XltxAnalyzer.new(@file_path)
      analyzer.analyze
    rescue => e
      Rails.logger.error("XLTX template analysis failed: #{e.message}")
      { error: e.message, format: "xltx" }
    end

    def extract_xlt_data
      # XLT (Legacy Excel template) - use specialized analyzer
      analyzer = Analyzers::XltAnalyzer.new(@file_path)
      analyzer.analyze
    rescue => e
      Rails.logger.error("XLT template analysis failed: #{e.message}")
      { error: e.message, format: "xlt" }
    end

    def extract_xltm_data
      # XLTM (Excel macro-enabled template) - use specialized analyzer
      analyzer = Analyzers::XltmAnalyzer.new(@file_path)
      analyzer.analyze
    rescue => e
      Rails.logger.error("XLTM template analysis failed: #{e.message}")
      { error: e.message, format: "xltm" }
    end

    def extract_ods_data
      # ODS (OpenDocument Spreadsheet) - use specialized analyzer
      analyzer = Analyzers::OdsAnalyzer.new(@file_path)
      analyzer.analyze
    rescue => e
      Rails.logger.error("ODS file analysis failed: #{e.message}")
      { error: e.message, format: "ods" }
    end

    def extract_csv_data
      require "csv"

      data = []
      CSV.foreach(@file_path, headers: true) do |row|
        data << row.to_h
      end

      {
        format: "csv",
        worksheets: [ {
          name: "Sheet1",
          data: data,
          row_count: data.count,
          column_count: data.first&.keys&.count || 0
        } ],
        metadata: {
          worksheet_count: 1
        }
      }
    rescue => e
      Rails.logger.error("CSV file analysis failed: #{e.message}")
      { error: e.message, format: "csv" }
    end

    def extract_worksheet_data(worksheet)
      data = []
      formulas = []

      worksheet.each_with_index do |row, row_index|
        next unless row

        row_data = []
        row.cells.each_with_index do |cell, col_index|
          next unless cell

          cell_data = {
            value: cell.value,
            datatype: cell.datatype,
            formula: cell.formula,
            row: row_index,
            col: col_index
          }

          row_data << cell_data

          # Collect formulas for analysis
          if cell.formula
            formulas << {
              formula: cell.formula,
              address: "#{RubyXL::Reference.ind2col(col_index)}#{row_index + 1}",
              row: row_index,
              col: col_index
            }
          end
        end

        data << row_data if row_data.any?
      end

      {
        name: worksheet.sheet_name,
        data: data,
        formulas: formulas,
        row_count: data.count,
        column_count: data.map(&:count).max || 0,
        formula_count: formulas.count
      }
    end

    def extract_roo_worksheet_data(spreadsheet, sheet_name)
      data = []
      formulas = []

      (spreadsheet.first_row..spreadsheet.last_row).each do |row|
        row_data = []
        (spreadsheet.first_column..spreadsheet.last_column).each do |col|
          cell_value = spreadsheet.cell(row, col)
          cell_formula = spreadsheet.formula(row, col)

          if cell_value || cell_formula
            cell_data = {
              value: cell_value,
              formula: cell_formula,
              row: row - 1, # Convert to 0-based
              col: col - 1  # Convert to 0-based
            }

            row_data << cell_data

            if cell_formula
              formulas << {
                formula: cell_formula,
                address: "#{('A'.ord + col - 1).chr}#{row}",
                row: row - 1,
                col: col - 1
              }
            end
          end
        end

        data << row_data if row_data.any?
      end

      {
        name: sheet_name,
        data: data,
        formulas: formulas,
        row_count: data.count,
        column_count: data.map(&:count).max || 0,
        formula_count: formulas.count
      }
    end
    end
  end
end
