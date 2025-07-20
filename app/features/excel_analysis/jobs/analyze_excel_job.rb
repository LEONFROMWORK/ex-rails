# frozen_string_literal: true

module ExcelAnalysis
  module Jobs
    class AnalyzeExcelJob < ApplicationJob
      queue_as :excel_processing

      def perform(excel_file_id:, user_id:)
        excel_file = ExcelFile.find(excel_file_id)
        user = User.find(user_id)

        # Update status
        excel_file.update!(status: "processing")
        broadcast_progress(excel_file, "Starting analysis...", 0)

        # Run error detection
        analyzer = ExcelAnalysis::Services::ErrorAnalyzerService.new(excel_file)
        errors_result = analyzer.analyze

        return handle_analysis_failure(excel_file, errors_result) if errors_result.failure?

        detected_errors = errors_result.value
        broadcast_progress(excel_file, "Found #{detected_errors.count} potential issues", 40)

        # Create analysis record
        analysis = excel_file.analyses.create!(
          user: user,
          detected_errors: detected_errors,
          status: "processing",
          error_count: detected_errors.count
        )

        # Queue AI analysis if errors found
        if detected_errors.any?
          AiIntegration::Jobs::AnalyzeErrorsJob.perform_later(
            analysis_id: analysis.id,
            user_tier: user.tier
          )
        else
          analysis.update!(
            status: "completed",
            ai_analysis: { summary: "No errors detected" },
            analysis_summary: "File is clean - no errors found"
          )
          excel_file.update!(status: "completed")
        end

        broadcast_progress(excel_file, "Analysis queued", 100)
      rescue StandardError => e
        excel_file.update!(status: "failed")
        broadcast_error(excel_file, e.message)
        raise
      end

      private

      def handle_analysis_failure(excel_file, result)
        excel_file.update!(status: "failed")
        broadcast_error(excel_file, result.error)
      end

      def broadcast_progress(excel_file, message, progress)
        ActionCable.server.broadcast(
          "excel_analysis_#{excel_file.id}",
          {
            type: "progress",
            message: message,
            progress: progress,
            timestamp: Time.current
          }
        )
      end

      def broadcast_error(excel_file, error_message)
        ActionCable.server.broadcast(
          "excel_analysis_#{excel_file.id}",
          {
            type: "error",
            message: error_message,
            timestamp: Time.current
          }
        )
      end
    end
  end
end
