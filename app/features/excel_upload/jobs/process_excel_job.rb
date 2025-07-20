# frozen_string_literal: true

module ExcelUpload
  module Jobs
    class ProcessExcelJob < ApplicationJob
      queue_as :excel_processing

      def perform(excel_file_id)
        excel_file = ExcelFile.find(excel_file_id)

        # Update status
        excel_file.update!(status: "processing")
        broadcast_progress(excel_file, "Starting file processing...", 0)

        # Extract metadata
        metadata_service = ExcelUpload::Services::MetadataExtractorService.new(excel_file)
        metadata_result = metadata_service.extract

        if metadata_result.success?
          excel_file.update!(
            metadata: metadata_result.value,
            sheet_count: metadata_result.value[:sheet_count],
            row_count: metadata_result.value[:total_rows],
            column_count: metadata_result.value[:max_columns]
          )
          broadcast_progress(excel_file, "Metadata extracted", 30)
        end

        # Trigger analysis
        ExcelAnalysis::Jobs::AnalyzeExcelJob.perform_later(
          excel_file_id: excel_file.id,
          user_id: excel_file.user_id
        )

        broadcast_progress(excel_file, "Queued for analysis", 100)
      rescue StandardError => e
        excel_file.update!(status: "failed")
        broadcast_error(excel_file, e.message)
        raise
      end

      private

      def broadcast_progress(excel_file, message, progress)
        ActionCable.server.broadcast(
          "excel_processing_#{excel_file.id}",
          {
            type: "progress",
            message: message,
            progress: progress,
            status: excel_file.status,
            timestamp: Time.current
          }
        )
      end

      def broadcast_error(excel_file, error_message)
        ActionCable.server.broadcast(
          "excel_processing_#{excel_file.id}",
          {
            type: "error",
            message: error_message,
            status: "failed",
            timestamp: Time.current
          }
        )
      end
    end
  end
end
