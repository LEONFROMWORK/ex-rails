# frozen_string_literal: true

module ExcelUpload
  module Handlers
    class ProcessUploadHandler < Common::BaseHandler
      MAX_FILE_SIZE = 50.megabytes
      ALLOWED_TYPES = %w[.xlsx .xls .csv .xlsm].freeze

      def initialize(file:, user:)
        @file = file
        @user = user
      end

      def execute
        # Validate file presence
        unless @file.present?
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "File is required"
            )
          )
        end

        # Validate user has sufficient credits
        unless @user.credits >= 10
          return Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Insufficient credits. You need at least 10 credits to upload a file.",
              code: "INSUFFICIENT_CREDITS"
            )
          )
        end

        # Validate file
        validation_result = validate_file
        return validation_result unless validation_result.success?

        begin
          # Process upload
          excel_file = process_file_upload

          # Queue analysis job
          ExcelAnalysisJob.perform_later(excel_file.id, @user.id)

          Rails.logger.info("File uploaded successfully: #{excel_file.id} by user #{@user.id}")

          Common::Result.success({
            file_id: excel_file.id,
            message: "File uploaded successfully and queued for analysis"
          })
        rescue StandardError => e
          Rails.logger.error("File upload failed: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "File upload failed: #{e.message}",
              code: "UPLOAD_ERROR"
            )
          )
        end
      end

      private

      def validate_file
        # Check file size
        if @file.size > MAX_FILE_SIZE
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "File too large. Maximum size is #{MAX_FILE_SIZE / 1.megabyte}MB"
            )
          )
        end

        # Check file type
        file_extension = File.extname(@file.original_filename).downcase
        unless ALLOWED_TYPES.include?(file_extension)
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "Invalid file type. Allowed types: #{ALLOWED_TYPES.join(', ')}"
            )
          )
        end

        # Check file is not empty
        if @file.size == 0
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "File is empty"
            )
          )
        end

        # Basic file corruption check
        unless valid_file_content?
          return Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "File appears to be corrupted or invalid"
            )
          )
        end

        Common::Result.success(true)
      end

      def valid_file_content?
        file_extension = File.extname(@file.original_filename).downcase

        case file_extension
        when ".xlsx", ".xlsm"
          validate_xlsx_content
        when ".xls"
          validate_xls_content
        when ".csv"
          validate_csv_content
        else
          false
        end
      end

      def validate_xlsx_content
        # Check for ZIP file signature (XLSX files are ZIP archives)
        @file.rewind
        signature = @file.read(4)
        @file.rewind

        signature == "PK\x03\x04"
      end

      def validate_xls_content
        # Check for OLE2 file signature (XLS files are OLE2 documents)
        @file.rewind
        signature = @file.read(8)
        @file.rewind

        signature == "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1"
      end

      def validate_csv_content
        # Basic CSV validation - check if it's readable text
        begin
          @file.rewind
          sample = @file.read(1024).force_encoding("UTF-8")
          @file.rewind

          # Check if it's valid UTF-8 and contains typical CSV characters
          sample.valid_encoding? && sample.match?(/[,;\t\n\r]/)
        rescue
          false
        end
      end

      def process_file_upload
        # Generate unique filename
        file_extension = File.extname(@file.original_filename)
        unique_filename = "#{SecureRandom.uuid}#{file_extension}"

        # Create upload directory if it doesn't exist
        upload_dir = Rails.root.join("storage", "uploads", "excel_files")
        FileUtils.mkdir_p(upload_dir)

        # Save file to disk
        file_path = upload_dir.join(unique_filename)
        File.open(file_path, "wb") do |f|
          @file.rewind
          f.write(@file.read)
        end

        # Create database record
        excel_file = @user.excel_files.create!(
          original_name: @file.original_filename,
          file_path: file_path.to_s,
          file_size: @file.size,
          status: "uploaded",
          content_type: @file.content_type
        )

        excel_file
      end
    end
  end
end
