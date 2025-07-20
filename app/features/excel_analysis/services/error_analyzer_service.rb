# frozen_string_literal: true

module ExcelAnalysis
  module Services
    class ErrorAnalyzerService
      attr_reader :file_path, :excel_file_record

      def initialize(excel_file_record)
        @excel_file_record = excel_file_record
        @file_path = excel_file_record.file_path
      end

      def analyze
        Rails.logger.info("Starting analysis for file: #{@file_path}")

        unless File.exist?(@file_path)
          return Common::Result.failure("File not found: #{@file_path}")
        end

        errors = []
        analysis_stats = {
          total_errors: 0,
          high_severity: 0,
          medium_severity: 0,
          low_severity: 0,
          modules_run: [],
          processing_time: 0
        }

        start_time = Time.current

        # Run different analysis modules with error handling per module
        analyzers = create_analyzers

        analyzers.each do |name, analyzer|
          begin
            Rails.logger.info("Running #{name} analysis...")
            module_start = Time.current

            module_result = analyzer.analyze(@file_path)
            module_errors = module_result.is_a?(Array) ? module_result : []

            errors.concat(module_errors)

            analysis_stats[:modules_run] << {
              name: name,
              errors_found: module_errors.size,
              processing_time: Time.current - module_start
            }

            Rails.logger.info("#{name} found #{module_errors.size} issues")

          rescue StandardError => e
            Rails.logger.error("#{name} analysis failed: #{e.message}")

            # Add a system error for failed module
            errors << {
              type: "analysis_error",
              severity: "high",
              module: name,
              message: "Analysis module failed: #{e.message}",
              description: "Error occurred during #{name} analysis",
              suggestion: "Contact support if this error persists"
            }
          end
        end

        # Process and sort errors
        processed_errors = process_errors(errors)
        analysis_stats.merge!(calculate_stats(processed_errors))
        analysis_stats[:processing_time] = Time.current - start_time

        Rails.logger.info("Analysis completed. Found #{processed_errors.size} total issues in #{analysis_stats[:processing_time].round(2)}s")

        Common::Result.success({
          errors: processed_errors,
          statistics: analysis_stats,
          file_info: extract_file_info
        })

      rescue StandardError => e
        Rails.logger.error("Critical error during analysis: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))

        Common::Result.failure(
          Common::Errors::FileProcessingError.new(
            message: "Analysis failed: #{e.message}",
            file_name: File.basename(@file_path)
          )
        )
      end

      private

      def create_analyzers
        {
          "formula_error_detector" => AnalyzeErrors::FormulaErrorDetector.new,
          "data_validation_checker" => AnalyzeErrors::DataValidationChecker.new,
          "circular_reference_detector" => AnalyzeErrors::CircularReferenceDetector.new,
          "format_consistency_checker" => AnalyzeErrors::FormatConsistencyChecker.new
        }
      end

      def process_errors(errors)
        # Remove duplicates based on cell and error type
        unique_errors = errors.uniq { |e| [ e[:cell], e[:type], e[:message] ] }

        # Sort errors by severity and then by cell location
        sorted_errors = unique_errors.sort_by do |error|
          [
            error_severity_weight(error[:severity]),
            extract_sheet_order(error[:cell] || ""),
            extract_cell_order(error[:cell] || "")
          ]
        end

        # Add error IDs for tracking
        sorted_errors.each_with_index do |error, index|
          error[:id] = "error_#{index + 1}"
          error[:timestamp] = Time.current.iso8601
        end

        sorted_errors
      end

      def calculate_stats(errors)
        stats = {
          total_errors: errors.size,
          high_severity: 0,
          medium_severity: 0,
          low_severity: 0
        }

        errors.each do |error|
          case error[:severity]&.downcase
          when "high", "critical"
            stats[:high_severity] += 1
          when "medium", "moderate"
            stats[:medium_severity] += 1
          when "low", "minor"
            stats[:low_severity] += 1
          end
        end

        stats
      end

      def extract_file_info
        return {} unless File.exist?(@file_path)

        {
          filename: File.basename(@file_path),
          size_bytes: File.size(@file_path),
          last_modified: File.mtime(@file_path),
          extension: File.extname(@file_path)
        }
      end

      def error_severity_weight(severity)
        case severity&.downcase
        when "high", "critical"
          1
        when "medium", "moderate"
          2
        when "low", "minor"
          3
        else
          4
        end
      end

      def extract_sheet_order(cell_address)
        # Extract sheet name for ordering (e.g., "Sheet1!A1" -> "Sheet1")
        cell_address.split("!").first || ""
      end

      def extract_cell_order(cell_address)
        # Extract cell reference for ordering (e.g., "Sheet1!A1" -> "A1")
        cell_ref = cell_address.split("!").last || ""

        # Convert to comparable format: column letters + row number
        match = cell_ref.match(/^([A-Z]+)(\d+)$/)
        return [ 0, 0 ] unless match

        col_letters = match[1]
        row_number = match[2].to_i

        # Convert column letters to number (A=1, B=2, ..., AA=27, etc.)
        col_number = col_letters.chars.reduce(0) do |acc, char|
          acc * 26 + (char.ord - "A".ord + 1)
        end

        [ col_number, row_number ]
      end
    end
  end
end
