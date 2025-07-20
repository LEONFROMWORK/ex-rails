# frozen_string_literal: true

module ExcelUpload
  module Handlers
    class UploadExcelHandler < Common::BaseHandler
      attr_reader :user, :file

      def initialize(user:, file:)
        @user = user
        @file = file
      end

      def execute
        # Validate file
        validator = ExcelUpload::Validators::ExcelFileValidator.new(file)
        validation_result = validator.validate
        return validation_result if validation_result.failure?

        # Store file
        storage_service = Infrastructure::FileStorage::S3Service.new
        file_path = storage_service.store(file, prefix: "excel_files/#{user.id}")

        # Calculate file hash
        file_hash = calculate_file_hash(file)

        # Create database record
        excel_file = user.excel_files.create!(
          original_name: file.original_filename,
          file_path: file_path,
          file_size: file.size,
          content_hash: file_hash,
          status: "uploaded",
          file_format: File.extname(file.original_filename).downcase
        )

        # Queue for processing
        ExcelUpload::Jobs::ProcessExcelJob.perform_later(excel_file.id)

        Common::Result.success(
          ExcelUpload::Models::UploadResponse.new(
            file_id: excel_file.id,
            status: "queued",
            message: "File uploaded successfully and queued for processing"
          )
        )
      rescue StandardError => e
        Rails.logger.error("Excel upload failed: #{e.message}")
        Common::Result.failure(
          Common::Errors::FileProcessingError.new(
            message: "Failed to upload file",
            file_name: file&.original_filename,
            details: { error: e.message }
          )
        )
      end

      private

      def calculate_file_hash(file)
        Digest::SHA256.hexdigest(file.read).tap { file.rewind }
      end
    end
  end
end
