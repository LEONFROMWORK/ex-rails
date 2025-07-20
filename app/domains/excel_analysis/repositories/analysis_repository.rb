# frozen_string_literal: true

module ExcelAnalysis
  module Repositories
    # Repository for analysis data access
    # Follows Single Responsibility Principle (SRP)
    class AnalysisRepository
      def create_from_result(file:, user_id:, result:)
        Analysis.create!(
          excel_file: file,
          user_id: user_id,
          detected_errors: result[:errors] || [],
          ai_analysis: result[:summary]&.to_json,
          structured_analysis: result[:structure]&.to_json,
          ai_tier_used: result[:ai_tier_used] || 1,
          confidence_score: result[:confidence_score] || 0.8,
          credits_used: result[:credits_used] || 0,
          provider: result[:provider] || "internal",
          status: "completed"
        )
      end

      def find_latest_for_file(file_id)
        Analysis.where(excel_file_id: file_id)
                .order(created_at: :desc)
                .first
      end

      def find_by_user(user_id, limit: 10)
        Analysis.joins(:excel_file)
                .where(excel_files: { user_id: user_id })
                .order(created_at: :desc)
                .limit(limit)
      end

      def update_status(analysis_id, status)
        analysis = Analysis.find(analysis_id)
        analysis.update!(status: status)
        analysis
      end
    end
  end
end
