# frozen_string_literal: true

module Admin
  module KnowledgeBase
    module Rag
      class EmbeddingJobsController < ApplicationController
        before_action :require_admin!

        def index
          render json: {
            success: true,
            jobs: fetch_embedding_jobs
          }
        end

        def create
          job_type = params[:type]

          unless valid_job_type?(job_type)
            render json: { error: "유효하지 않은 임베딩 작업 타입입니다" }, status: :bad_request
            return
          end

          # Check for active jobs
          if active_jobs_exist?
            render json: { error: "이미 진행 중인 임베딩 작업이 있습니다" }, status: :conflict
            return
          end

          job_id = start_embedding_job(job_type)

          render json: {
            success: true,
            job_id: job_id,
            message: "#{job_type_text(job_type)} 작업이 시작되었습니다"
          }
        end

        private

        def valid_job_type?(type)
          %w[full_reindex incremental cleanup].include?(type)
        end

        def active_jobs_exist?
          # In production, check for active background jobs
          false
        end

        def start_embedding_job(type)
          job_id = SecureRandom.uuid

          # In production, enqueue background job
          # EmbeddingProcessorJob.perform_later(job_id, type, current_user.id)

          Rails.logger.info "Started embedding job: #{job_id} (#{type})"
          job_id
        end

        def job_type_text(type)
          case type
          when "full_reindex" then "전체 재색인"
          when "incremental" then "증분 색인"
          when "cleanup" then "정리 작업"
          else type
          end
        end

        def fetch_embedding_jobs
          [
            {
              id: "embed_001",
              type: "incremental",
              status: "running",
              progress: 67,
              documents_processed: 1580,
              total_documents: 2340,
              started_at: 25.minutes.ago.iso8601
            },
            {
              id: "embed_002",
              type: "full_reindex",
              status: "completed",
              progress: 100,
              documents_processed: 15420,
              total_documents: 15420,
              started_at: 2.days.ago.iso8601,
              completed_at: (2.days.ago + 45.minutes).iso8601
            },
            {
              id: "embed_003",
              type: "cleanup",
              status: "completed",
              progress: 100,
              documents_processed: 342,
              total_documents: 342,
              started_at: 5.days.ago.iso8601,
              completed_at: (5.days.ago + 8.minutes).iso8601
            },
            {
              id: "embed_004",
              type: "incremental",
              status: "failed",
              progress: 23,
              documents_processed: 287,
              total_documents: 1250,
              started_at: 7.days.ago.iso8601,
              error: "OpenAI API 요청 한도 초과"
            }
          ]
        end
      end
    end
  end
end
