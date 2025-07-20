# frozen_string_literal: true

module ExcelAnalysis
  module Repositories
    # Repository for Excel file data access
    # Follows Single Responsibility Principle (SRP) and Repository Pattern
    class FileRepository
      def find_by_id_and_user(file_id, user_id)
        ExcelFile.find_by(id: file_id, user_id: user_id)
      end

      def find_by_id(file_id)
        ExcelFile.find_by(id: file_id)
      end

      def find_analyzable_files(user_id, limit: 10)
        ExcelFile.where(user_id: user_id)
                 .where(status: [ "uploaded", "failed" ])
                 .order(created_at: :desc)
                 .limit(limit)
      end

      def update_status(file_id, status)
        file = ExcelFile.find(file_id)
        file.update!(status: status)
        file
      end

      def find_with_metadata(file_id, user_id)
        ExcelFile.includes(:analyses)
                 .find_by(id: file_id, user_id: user_id)
      end
    end
  end
end
