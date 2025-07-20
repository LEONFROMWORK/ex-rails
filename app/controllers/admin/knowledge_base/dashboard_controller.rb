# frozen_string_literal: true

module Admin
  module KnowledgeBase
    class DashboardController < ApplicationController
      before_action :require_admin!

      def index
        @knowledge_base_stats = fetch_knowledge_base_stats
        @processing_jobs = fetch_processing_jobs
      end

      private

      def fetch_knowledge_base_stats
        # In production, this would query actual database
        {
          total_documents: 15420,
          total_embeddings: 15420,
          categories: {
            "함수오류" => 4250,
            "데이터처리" => 3890,
            "차트생성" => 2340,
            "매크로/VBA" => 2180,
            "조건부서식" => 1560,
            "피벗테이블" => 1200
          },
          last_updated: 6.hours.ago,
          processing_jobs: 1
        }
      end

      def fetch_processing_jobs
        # In production, this would query actual background jobs
        [
          {
            id: "job_001",
            type: "embedding",
            status: "running",
            progress: 67,
            processed_items: 1580,
            total_items: 2340,
            created_at: 25.minutes.ago,
            error: nil
          }
        ]
      end
    end
  end
end
