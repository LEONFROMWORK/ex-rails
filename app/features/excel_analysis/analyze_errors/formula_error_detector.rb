# frozen_string_literal: true

module ExcelAnalysis
  module AnalyzeErrors
    class FormulaErrorDetector
      EXCEL_ERRORS = [
        "#DIV/0!", "#N/A", "#NAME?", "#NULL!",
        "#NUM!", "#REF!", "#VALUE!", "#SPILL!", "#CALC!"
      ].freeze

      def initialize
        @workbook = nil
      end

      def analyze(file_path)
        errors = []
        return errors unless File.exist?(file_path)

        begin
          @workbook = Roo::Spreadsheet.open(file_path)

          @workbook.sheets.each do |sheet_name|
            @workbook.default_sheet = sheet_name
            sheet_errors = analyze_sheet(sheet_name)
            errors.concat(sheet_errors)
          end
        rescue StandardError => e
          Rails.logger.error("Error analyzing Excel file: #{e.message}")
          errors << create_file_error(e.message)
        ensure
          @workbook&.close if @workbook.respond_to?(:close)
        end

        errors
      end

      private

      def analyze_sheet(sheet_name)
        errors = []
        return errors unless @workbook

        (1..@workbook.last_row).each do |row|
          (1..@workbook.last_column).each do |col|
            cell_errors = analyze_cell(sheet_name, row, col)
            errors.concat(cell_errors)
          end
        end

        errors
      end

      def analyze_cell(sheet_name, row, col)
        errors = []
        cell_address = "#{sheet_name}!#{Roo::Base.number_to_letter(col)}#{row}"

        begin
          cell_value = @workbook.cell(row, col)
          cell_formula = @workbook.formula(row, col) if @workbook.respond_to?(:formula)

          # Check for Excel error values
          if cell_value.is_a?(String) && EXCEL_ERRORS.include?(cell_value)
            errors << create_formula_error(cell_address, cell_value, cell_formula)
          end

          # Check for problematic formulas even if they don't show errors yet
          if cell_formula.present?
            formula_errors = analyze_formula_syntax(cell_address, cell_formula)
            errors.concat(formula_errors)
          end

        rescue StandardError => e
          Rails.logger.warn("Error reading cell #{cell_address}: #{e.message}")
        end

        errors
      end

      def analyze_formula_syntax(cell_address, formula)
        errors = []

        # Check for common formula issues
        errors.concat(check_division_by_zero_risk(cell_address, formula))
        errors.concat(check_circular_references(cell_address, formula))
        errors.concat(check_function_misspellings(cell_address, formula))
        errors.concat(check_range_issues(cell_address, formula))

        errors
      end

      def check_division_by_zero_risk(cell_address, formula)
        errors = []

        # Look for division operations that might cause #DIV/0!
        if formula.match?(%r{/[A-Z]+\d+}i) && !formula.match?(/IFERROR|IF\s*\(/i)
          errors << {
            type: "potential_formula_error",
            severity: "medium",
            cell: cell_address,
            error_type: "division_risk",
            message: "Potential division by zero risk",
            formula: formula,
            description: "Formula contains division that could result in #DIV/0! error",
            suggestion: "Consider adding IFERROR or IF function to handle division by zero"
          }
        end

        errors
      end

      def check_circular_references(cell_address, formula)
        errors = []

        # Extract current cell reference
        current_cell = cell_address.split("!").last

        # Check if formula references itself
        if formula.include?(current_cell)
          errors << {
            type: "formula_error",
            severity: "high",
            cell: cell_address,
            error_type: "circular_reference",
            message: "Circular reference detected",
            formula: formula,
            description: "Formula references itself, creating a circular dependency",
            suggestion: "Remove self-reference or restructure the calculation"
          }
        end

        errors
      end

      def check_function_misspellings(cell_address, formula)
        errors = []

        # Common misspellings
        misspellings = {
          "SUMM" => "SUM",
          "AVERGE" => "AVERAGE",
          "COUTN" => "COUNT",
          "COUTNA" => "COUNTA",
          "VLOKUP" => "VLOOKUP",
          "HLOKUP" => "HLOOKUP",
          "CONCATENAT" => "CONCATENATE"
        }

        misspellings.each do |wrong, correct|
          if formula.include?(wrong)
            errors << {
              type: "formula_error",
              severity: "high",
              cell: cell_address,
              error_type: "function_misspelling",
              message: "Misspelled function: #{wrong}",
              formula: formula,
              description: "Function '#{wrong}' is misspelled and will cause #NAME? error",
              suggestion: "Correct spelling to '#{correct}'"
            }
          end
        end

        errors
      end

      def check_range_issues(cell_address, formula)
        errors = []

        # Check for entire column references that might be inefficient
        if formula.match?(/[A-Z]+:[A-Z]+/i)
          errors << {
            type: "performance_warning",
            severity: "low",
            cell: cell_address,
            error_type: "inefficient_range",
            message: "Entire column reference detected",
            formula: formula,
            description: "Using entire column references can impact performance",
            suggestion: "Consider using specific ranges like A1:A1000 instead of A:A"
          }
        end

        errors
      end

      def create_formula_error(cell_address, error_value, formula)
        severity = case error_value
        when "#DIV/0!", "#REF!", "#NAME?" then "high"
        when "#N/A", "#VALUE!" then "medium"
        else "low"
        end

        {
          type: "formula_error",
          severity: severity,
          cell: cell_address,
          error_type: error_value,
          message: get_error_message(error_value),
          formula: formula || "Unknown",
          description: get_error_description(error_value),
          suggestion: get_error_suggestion(error_value)
        }
      end

      def create_file_error(message)
        {
          type: "file_error",
          severity: "high",
          cell: "N/A",
          error_type: "file_processing",
          message: "File processing error: #{message}",
          formula: "N/A",
          description: "Unable to process Excel file",
          suggestion: "Check file format and ensure it is not corrupted"
        }
      end

      def get_error_message(error_value)
        case error_value
        when "#DIV/0!" then "Division by zero error"
        when "#N/A" then "Value not available"
        when "#NAME?" then "Unrecognized function or name"
        when "#NULL!" then "Null intersection error"
        when "#NUM!" then "Invalid numeric value"
        when "#REF!" then "Invalid cell reference"
        when "#VALUE!" then "Wrong data type"
        when "#SPILL!" then "Spill range error"
        when "#CALC!" then "Calculation error"
        else "Unknown Excel error"
        end
      end

      def get_error_description(error_value)
        case error_value
        when "#DIV/0!" then "Formula attempts to divide by zero or empty cell"
        when "#N/A" then "Function cannot find referenced value"
        when "#NAME?" then "Function name is misspelled or not recognized"
        when "#NULL!" then "Formula refers to intersection of ranges that do not intersect"
        when "#NUM!" then "Formula contains invalid numeric values"
        when "#REF!" then "Formula contains reference to deleted or invalid cells"
        when "#VALUE!" then "Formula contains wrong data type for operation"
        when "#SPILL!" then "Dynamic array formula cannot spill into required cells"
        when "#CALC!" then "Error in calculation engine"
        else "Unrecognized Excel error"
        end
      end

      def get_error_suggestion(error_value)
        case error_value
        when "#DIV/0!" then "Use IF or IFERROR function to handle division by zero"
        when "#N/A" then "Check lookup values and ranges, consider using IFERROR"
        when "#NAME?" then "Check function spelling and defined names"
        when "#NULL!" then "Review range references and intersection logic"
        when "#NUM!" then "Verify numeric values and function arguments"
        when "#REF!" then "Update references to valid cells"
        when "#VALUE!" then "Check data types and format consistency"
        when "#SPILL!" then "Clear cells or resize spill range"
        when "#CALC!" then "Check for circular references or complex calculations"
        else "Review formula logic and syntax"
        end
      end
    end
  end
end
