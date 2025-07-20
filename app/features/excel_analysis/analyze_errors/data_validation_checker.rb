# frozen_string_literal: true

module ExcelAnalysis
  module AnalyzeErrors
    class DataValidationChecker
      def initialize
        @workbook = nil
        @cell_references = Set.new
      end

      def analyze(file_path)
        errors = []
        return errors unless File.exist?(file_path)

        begin
          @workbook = Roo::Spreadsheet.open(file_path)

          # First pass: collect all cell references used in formulas
          collect_cell_references

          # Second pass: validate data
          @workbook.sheets.each do |sheet_name|
            @workbook.default_sheet = sheet_name
            sheet_errors = analyze_sheet(sheet_name)
            errors.concat(sheet_errors)
          end
        rescue StandardError => e
          Rails.logger.error("Error in data validation analysis: #{e.message}")
          errors << create_file_error(e.message)
        ensure
          @workbook&.close if @workbook.respond_to?(:close)
        end

        errors
      end

      private

      def collect_cell_references
        return unless @workbook

        @workbook.sheets.each do |sheet_name|
          @workbook.default_sheet = sheet_name

          (1..@workbook.last_row).each do |row|
            (1..@workbook.last_column).each do |col|
              formula = @workbook.formula(row, col) if @workbook.respond_to?(:formula)
              next unless formula.present?

              # Extract cell references from formula
              cell_refs = formula.scan(/[A-Z]+\d+/i)
              cell_refs.each { |ref| @cell_references.add("#{sheet_name}!#{ref}") }
            end
          end
        end
      end

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

          # Skip empty cells unless they're referenced by formulas
          if cell_value.nil? || cell_value.to_s.strip.empty?
            if @cell_references.include?(cell_address)
              errors << create_missing_data_error(cell_address)
            end
            return errors
          end

          # Check data type consistency in columns
          errors.concat(check_data_type_consistency(sheet_name, row, col, cell_value))

          # Check for common data quality issues
          errors.concat(check_data_quality_issues(cell_address, cell_value))

          # Check for numeric range issues
          errors.concat(check_numeric_ranges(cell_address, cell_value))

        rescue StandardError => e
          Rails.logger.warn("Error validating cell #{cell_address}: #{e.message}")
        end

        errors
      end

      def check_data_type_consistency(sheet_name, row, col, cell_value)
        errors = []

        # Check if column has mixed data types
        column_values = []
        (1..@workbook.last_row).each do |r|
          val = @workbook.cell(r, col)
          column_values << val unless val.nil? || val.to_s.strip.empty?
        end

        return errors if column_values.size < 3 # Not enough data to determine pattern

        # Determine the predominant data type in the column
        type_counts = column_values.group_by { |v| classify_data_type(v) }
        predominant_type = type_counts.max_by { |_, values| values.size }.first

        current_type = classify_data_type(cell_value)

        if current_type != predominant_type && type_counts.size > 1
          errors << {
            type: "data_consistency",
            severity: "medium",
            cell: "#{sheet_name}!#{Roo::Base.number_to_letter(col)}#{row}",
            message: "Inconsistent data type in column",
            expected_type: predominant_type,
            actual_type: current_type,
            value: cell_value,
            description: "Most cells in column #{Roo::Base.number_to_letter(col)} contain #{predominant_type} data",
            suggestion: "Consider converting to #{predominant_type} or reviewing data entry"
          }
        end

        errors
      end

      def check_data_quality_issues(cell_address, cell_value)
        errors = []

        if cell_value.is_a?(String)
          # Check for common text issues
          errors.concat(check_text_quality(cell_address, cell_value))
        elsif cell_value.is_a?(Numeric)
          # Check for numeric quality issues
          errors.concat(check_numeric_quality(cell_address, cell_value))
        end

        errors
      end

      def check_text_quality(cell_address, text_value)
        errors = []

        # Check for leading/trailing spaces
        if text_value != text_value.strip
          errors << {
            type: "data_quality",
            severity: "low",
            cell: cell_address,
            message: "Leading or trailing spaces detected",
            value: text_value,
            description: "Text contains unnecessary whitespace",
            suggestion: "Remove leading and trailing spaces using TRIM function"
          }
        end

        # Check for potential numeric data stored as text
        if text_value.match?(/^\d+\.?\d*$/) && text_value.length > 1
          errors << {
            type: "data_type_mismatch",
            severity: "medium",
            cell: cell_address,
            message: "Numeric data stored as text",
            value: text_value,
            description: "Value appears to be numeric but stored as text",
            suggestion: "Convert to number format using VALUE function or formatting"
          }
        end

        # Check for inconsistent case
        if text_value.match?(/[a-z]/) && text_value.match?(/[A-Z]/) && text_value.length > 5
          words = text_value.split(/\s+/)
          if words.any? { |word| word.match?(/[a-z]/) && word.match?(/[A-Z]/) }
            errors << {
              type: "data_quality",
              severity: "low",
              cell: cell_address,
              message: "Inconsistent text capitalization",
              value: text_value,
              description: "Text has mixed capitalization patterns",
              suggestion: "Consider standardizing to UPPER, LOWER, or PROPER case"
            }
          end
        end

        errors
      end

      def check_numeric_quality(cell_address, numeric_value)
        errors = []

        # Check for extremely large or small numbers
        if numeric_value.abs > 1_000_000_000
          errors << {
            type: "data_quality",
            severity: "low",
            cell: cell_address,
            message: "Extremely large number",
            value: numeric_value,
            description: "Number may be too large for typical calculations",
            suggestion: "Verify if this value is correct or consider scaling"
          }
        end

        # Check for precision issues (too many decimal places)
        if numeric_value.is_a?(Float) && numeric_value.to_s.split(".")[1]&.length.to_i > 10
          errors << {
            type: "data_quality",
            severity: "low",
            cell: cell_address,
            message: "Excessive decimal precision",
            value: numeric_value,
            description: "Number has more decimal places than typically needed",
            suggestion: "Consider rounding to appropriate precision using ROUND function"
          }
        end

        errors
      end

      def check_numeric_ranges(cell_address, cell_value)
        errors = []
        return errors unless cell_value.is_a?(Numeric)

        # Check for common business logic ranges

        # Percentage values
        if cell_address.downcase.include?("percent") || cell_address.downcase.include?("%")
          if cell_value < 0 || cell_value > 100
            errors << {
              type: "data_validation",
              severity: "medium",
              cell: cell_address,
              message: "Percentage value outside valid range",
              value: cell_value,
              valid_range: "0-100",
              description: "Percentage values should typically be between 0 and 100",
              suggestion: "Verify if value should be converted or if range is correct"
            }
          end
        end

        # Age values (common in HR data)
        if cell_address.downcase.include?("age")
          if cell_value < 0 || cell_value > 150
            errors << {
              type: "data_validation",
              severity: "high",
              cell: cell_address,
              message: "Age value outside realistic range",
              value: cell_value,
              valid_range: "0-150",
              description: "Age values should be realistic",
              suggestion: "Verify data entry for age field"
            }
          end
        end

        # Negative values where they might not make sense
        if cell_value < 0
          suspicious_fields = [ "quantity", "count", "amount", "total", "sum" ]
          if suspicious_fields.any? { |field| cell_address.downcase.include?(field) }
            errors << {
              type: "data_validation",
              severity: "medium",
              cell: cell_address,
              message: "Negative value in field that typically should be positive",
              value: cell_value,
              description: "Field contains negative value which may be incorrect",
              suggestion: "Verify if negative value is intentional"
            }
          end
        end

        errors
      end

      def classify_data_type(value)
        return "empty" if value.nil? || value.to_s.strip.empty?
        return "number" if value.is_a?(Numeric)
        return "date" if value.is_a?(Date) || value.is_a?(Time)
        return "boolean" if [ true, false ].include?(value)

        # For strings, try to determine more specific type
        string_val = value.to_s.strip
        return "number_as_text" if string_val.match?(/^\d+\.?\d*$/)
        "text"
      end

      def create_missing_data_error(cell_address)
        {
          type: "missing_data",
          severity: "medium",
          cell: cell_address,
          message: "Referenced cell is empty",
          description: "This cell is referenced by a formula but contains no data",
          suggestion: "Fill in the missing data or update dependent formulas"
        }
      end

      def create_file_error(message)
        {
          type: "file_error",
          severity: "high",
          cell: "N/A",
          error_type: "data_validation_error",
          message: "Data validation error: #{message}",
          description: "Unable to validate Excel file data",
          suggestion: "Check file format and ensure it is not corrupted"
        }
      end
    end
  end
end
