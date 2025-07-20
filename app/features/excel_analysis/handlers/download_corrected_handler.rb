# frozen_string_literal: true

module ExcelAnalysis
  module Handlers
    class DownloadCorrectedHandler < Common::BaseHandler
      def initialize(excel_file:, user:)
        @excel_file = excel_file
        @user = user
      end

      def execute
        # Validate preconditions
        validation_result = validate_request
        return validation_result if validation_result.failure?

        # Generate corrected file using optimized generator
        begin
          analysis = @excel_file.latest_analysis

          # Prepare analysis result for optimized generator
          analysis_result = prepare_analysis_result(analysis)

          # Use optimized Excel generator for better performance
          generator = ExcelAnalysis::Services::OptimizedExcelGenerator.new(
            analysis_result,
            {
              include_corrections: true,
              include_analysis_summary: true,
              output_format: :xlsx,
              performance_mode: determine_performance_mode
            }
          )

          result = generator.generate_corrected_file

          # Log performance metrics
          if result[:generation_metrics]
            Rails.logger.info(
              "Excel generation performance: " \
              "#{result[:generation_metrics][:generation_strategy]} strategy, " \
              "#{result[:generation_metrics][:generation_time_seconds]}s, " \
              "#{result[:generation_metrics][:throughput_rows_per_second]} rows/s"
            )
          end

          Rails.logger.info("Corrected file generated for Excel file #{@excel_file.id} using #{result[:generator]}")

          Common::Result.success({
            content: result[:file_data],
            filename: result[:filename] || "corrected_#{@excel_file.original_name}",
            content_type: result[:content_type] || determine_content_type,
            excel_file: @excel_file,
            performance_info: {
              generator: result[:generator],
              performance_gain: result[:performance_gain],
              generation_time: result[:generation_metrics]&.[](:generation_time_seconds)
            }
          })
        rescue StandardError => e
          Rails.logger.error("Optimized generation failed, falling back to standard generator: #{e.message}")

          # Fallback to original generator
          fallback_result = generate_with_fallback(analysis)
          return fallback_result if fallback_result

          Common::Result.failure(
            Common::Errors::FileProcessingError.new(
              message: "Failed to generate corrected file",
              file_name: @excel_file.original_name
            )
          )
        rescue StandardError => e
          Rails.logger.error("Error generating corrected file: #{e.message}")
          Common::Result.failure(
            Common::Errors::FileProcessingError.new(
              message: "Error generating corrected file: #{e.message}",
              file_name: @excel_file.original_name
            )
          )
        end
      end

      private

      def validate_request
        errors = []

        # Check if analysis exists and is completed
        analysis = @excel_file.latest_analysis
        unless analysis&.completed?
          errors << "No completed analysis available"
        end

        # Check if corrections are available
        unless analysis&.corrections.present?
          errors << "No corrections available to generate file"
        end

        # Check user owns the file
        unless @excel_file.user == @user
          errors << "You don't have permission to download this file"
        end

        return Common::Result.success if errors.empty?

        Common::Result.failure(
          Common::Errors::ValidationError.new(
            message: "Download validation failed",
            details: { errors: errors }
          )
        )
      end

      def prepare_analysis_result(analysis)
        # Convert analysis data to format expected by optimized generator
        {
          worksheets: extract_worksheet_data_from_analysis(analysis),
          errors: analysis.detected_errors || [],
          metadata: {
            original_filename: @excel_file.original_name,
            file_size: @excel_file.file_size,
            analysis_date: analysis.created_at
          },
          processor: "analysis_result",
          performance_metrics: {
            analysis_time: analysis.created_at ? (analysis.updated_at - analysis.created_at) : 0,
            ai_tier_used: analysis.ai_tier_used,
            credits_used: analysis.credits_used
          }
        }
      end

      def extract_worksheet_data_from_analysis(analysis)
        # Extract worksheet information from analysis
        # This would typically come from the original analysis data
        if analysis.structured_analysis&.dig("worksheets")
          analysis.structured_analysis["worksheets"]
        else
          # Fallback: create basic worksheet structure
          [ {
            name: "Corrected Data",
            data: [],
            errors: analysis.detected_errors || [],
            row_count: 0,
            column_count: 0
          } ]
        end
      end

      def determine_performance_mode
        # Determine optimal performance mode based on file characteristics
        if @excel_file.file_size < 1.megabyte
          :fast_excel
        elsif @excel_file.file_size < 10.megabytes
          :xlsxtream
        else
          :hybrid
        end
      end

      def generate_with_fallback(analysis)
        # Fallback to original corrected file generator if it exists
        if defined?(ExcelAnalysis::Services::CorrectedFileGenerator)
          begin
            generator = ExcelAnalysis::Services::CorrectedFileGenerator.new(
              excel_file: @excel_file,
              analysis: analysis
            )

            result = generator.generate

            if result.success?
              Rails.logger.info("Fallback corrected file generated for Excel file #{@excel_file.id}")

              return Common::Result.success({
                content: result.value[:content],
                filename: "corrected_#{@excel_file.original_name}",
                content_type: determine_content_type,
                excel_file: @excel_file,
                performance_info: {
                  generator: "fallback",
                  performance_gain: "Standard generation",
                  generation_time: nil
                }
              })
            end
          rescue StandardError => e
            Rails.logger.error("Fallback generation also failed: #{e.message}")
          end
        end

        nil
      end

      def determine_content_type
        extension = File.extname(@excel_file.original_name).downcase

        case extension
        when ".xlsx"
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        when ".xls"
          "application/vnd.ms-excel"
        when ".csv"
          "text/csv"
        else
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        end
      end
    end
  end
end
