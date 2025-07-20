# frozen_string_literal: true

module ExcelAnalysis
  module Queries
    # Query for getting analysis status
    # Follows Single Responsibility Principle (SRP) and Query Pattern
    class GetAnalysisStatus < Shared::Contracts::Query
      include ActiveModel::Attributes

      attribute :file_id, :integer
      attribute :user_id, :integer

      validates :file_id, :user_id, presence: true

      def initialize(dependencies = {})
        super()
        @file_repository = dependencies[:file_repository] || ExcelAnalysis::Repositories::FileRepository.new
        @analysis_repository = dependencies[:analysis_repository] || ExcelAnalysis::Repositories::AnalysisRepository.new
      end

      private

      def fetch_data
        file = @file_repository.find_by_id_and_user(file_id, user_id)
        return Shared::Types::Result.failure(error: "File not found") unless file

        latest_analysis = @analysis_repository.find_latest_for_file(file_id)

        status_data = {
          file: {
            id: file.id,
            name: file.original_name,
            status: file.status,
            size: file.file_size,
            uploaded_at: file.created_at
          }
        }

        if latest_analysis
          status_data[:analysis] = {
            id: latest_analysis.id,
            status: latest_analysis.status,
            errors_found: latest_analysis.detected_errors&.count || 0,
            confidence_score: latest_analysis.confidence_score,
            created_at: latest_analysis.created_at,
            ai_tier_used: latest_analysis.ai_tier_used,
            credits_used: latest_analysis.credits_used
          }
        else
          status_data[:analysis] = nil
        end

        # Check for VBA presence
        status_data[:has_vba] = detect_vba_in_file(file)

        Shared::Types::Result.success(value: status_data)
      rescue => error
        Shared::Types::Result.failure(error: "Failed to get status: #{error.message}")
      end

      def detect_vba_in_file(file)
        # Simple heuristic based on file extension and size
        macro_extensions = %w[.xlsm .xltm .xlam]
        has_macro_extension = macro_extensions.any? { |ext| file.original_name.downcase.include?(ext) }

        # Also consider larger files more likely to have macros
        potentially_has_macros = file.file_size > 50.kilobytes

        has_macro_extension || potentially_has_macros
      end
    end
  end
end
