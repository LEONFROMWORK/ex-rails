# frozen_string_literal: true

module ExcelUpload
  module Models
    class UploadResponse
      attr_reader :file_id, :status, :message

      def initialize(file_id:, status:, message:)
        @file_id = file_id
        @status = status
        @message = message
      end

      def to_h
        {
          file_id: file_id,
          status: status,
          message: message
        }
      end
    end
  end
end
