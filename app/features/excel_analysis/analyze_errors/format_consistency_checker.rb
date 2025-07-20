# frozen_string_literal: true

module ExcelAnalysis
  module AnalyzeErrors
    class FormatConsistencyChecker
      def analyze(excel_file)
        errors = []

        # Mock implementation for format consistency checking

        if rand > 0.7
          errors << {
            type: "format_inconsistency",
            severity: "low",
            cells: [ "A1:A10" ],
            message: "Inconsistent number formatting",
            formats_found: [ "General", "0.00", "#,##0" ],
            description: "Column contains mixed number formats",
            suggestion: "Apply consistent formatting to the entire column"
          }
        end

        if rand > 0.8
          errors << {
            type: "format_inconsistency",
            severity: "low",
            cells: [ "B1:B20" ],
            message: "Inconsistent date formatting",
            formats_found: [ "MM/DD/YYYY", "DD/MM/YYYY", "YYYY-MM-DD" ],
            description: "Date column uses multiple date formats",
            suggestion: "Standardize date format across all cells"
          }
        end

        errors
      end
    end
  end
end
