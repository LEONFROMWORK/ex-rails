# frozen_string_literal: true

module Admin
  module KnowledgeBase
    class DatasetsController < ApplicationController
      before_action :require_admin!

      def index
        @datasets = fetch_datasets

        if request.xhr?
          render json: { success: true, datasets: @datasets }
        end
      end

      def create
        # Handle file upload and processing
        file = params[:file]

        if file.blank?
          render json: { error: "파일을 선택해주세요" }, status: :bad_request
          return
        end

        # In production, would process the uploaded file
        dataset_id = SecureRandom.uuid

        render json: {
          success: true,
          dataset_id: dataset_id,
          message: "데이터셋 업로드가 시작되었습니다"
        }
      end

      def show
        dataset_id = params[:id]
        dataset = find_dataset(dataset_id)

        if dataset
          render json: { success: true, dataset: dataset }
        else
          render json: { error: "데이터셋을 찾을 수 없습니다" }, status: :not_found
        end
      end

      def process
        dataset_id = params[:id]

        # In production, would start background processing job
        Rails.logger.info "Starting dataset processing: #{dataset_id}"

        render json: {
          success: true,
          message: "데이터셋 처리가 시작되었습니다"
        }
      end

      def destroy
        dataset_id = params[:id]

        # In production, would delete the dataset
        Rails.logger.info "Deleting dataset: #{dataset_id}"

        render json: {
          success: true,
          message: "데이터셋이 삭제되었습니다"
        }
      end

      private

      def fetch_datasets
        # Mock data - in production, would query actual datasets
        [
          {
            id: "dataset_001",
            name: "Stack Overflow Excel Q&A",
            file_type: "JSONL",
            file_size: "45.2 MB",
            record_count: 8945,
            status: "processed",
            uploaded_at: 3.days.ago.iso8601,
            processed_at: 3.days.ago.iso8601
          },
          {
            id: "dataset_002",
            name: "Reddit Excel Forum",
            file_type: "JSONL",
            file_size: "32.1 MB",
            record_count: 6475,
            status: "processing",
            uploaded_at: 1.day.ago.iso8601,
            processed_at: nil
          }
        ]
      end

      def find_dataset(id)
        fetch_datasets.find { |d| d[:id] == id }
      end
    end
  end
end
