# frozen_string_literal: true

module ExcelUpload
  module Validators
    class ExcelFileValidator
      MAX_FILE_SIZE = 50.megabytes
      ALLOWED_EXTENSIONS = %w[.xlsx .xls .csv .xlsm].freeze
      ALLOWED_MIME_TYPES = [
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "text/csv",
        "application/vnd.ms-excel.sheet.macroEnabled.12"
      ].freeze

      attr_reader :file

      def initialize(file)
        @file = file
      end

      def validate
        errors = []

        errors << "File is required" if file.nil?
        return Common::Result.failure(errors) if file.nil?

        errors << "File too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)" if file.size > MAX_FILE_SIZE
        errors << "Invalid file type" unless valid_extension? && valid_mime_type?
        errors << "File appears to be corrupted" unless valid_file_structure?

        errors.empty? ? Common::Result.success : Common::Result.failure(errors)
      end

      private

      def valid_extension?
        return false unless file.original_filename.present?

        extension = File.extname(file.original_filename).downcase
        ALLOWED_EXTENSIONS.include?(extension)
      end

      def valid_mime_type?
        ALLOWED_MIME_TYPES.include?(file.content_type)
      end

      def valid_file_structure?
        # Basic check - try to read first few bytes
        begin
          file.rewind
          header = file.read(8)
          file.rewind

          # Check for Excel file signatures
          case File.extname(file.original_filename).downcase
          when ".xlsx", ".xlsm"
            # XLSX files start with PK (ZIP format)
            header&.start_with?("PK")
          when ".xls"
            # XLS files have specific header
            header&.bytes&.first(4) == [ 0xD0, 0xCF, 0x11, 0xE0 ]
          when ".csv"
            # CSV files should be readable as text
            true
          else
            false
          end
        rescue StandardError
          false
        end
      end
    end
  end
end
