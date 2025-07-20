# frozen_string_literal: true

module Admin
  module KnowledgeBase
    class LearningController < ApplicationController
      before_action :require_admin!

      def index
        @learning_stats = fetch_learning_stats
        @training_metrics = fetch_training_metrics
        @model_status = fetch_model_status
      end

      def metrics
        render json: {
          success: true,
          metrics: fetch_training_metrics
        }
      end

      def start_training
        training_type = params[:type] || "incremental"

        # In production, would start actual training job
        job_id = SecureRandom.uuid
        Rails.logger.info "Starting training job: #{job_id} (#{training_type})"

        render json: {
          success: true,
          job_id: job_id,
          message: "모델 학습이 시작되었습니다"
        }
      end

      def stop_training
        job_id = params[:job_id]

        # In production, would stop the training job
        Rails.logger.info "Stopping training job: #{job_id}"

        render json: {
          success: true,
          message: "모델 학습이 중단되었습니다"
        }
      end

      private

      def fetch_learning_stats
        {
          total_training_data: 15420,
          training_accuracy: 94.2,
          validation_accuracy: 91.8,
          last_training: 2.days.ago,
          model_version: "v2.1.0",
          training_status: "completed"
        }
      end

      def fetch_training_metrics
        {
          epochs_completed: 50,
          total_epochs: 50,
          current_loss: 0.023,
          validation_loss: 0.031,
          learning_rate: 0.0001,
          training_time: "2h 34m",
          convergence_rate: 98.5
        }
      end

      def fetch_model_status
        [
          {
            id: "model_001",
            name: "Excel Error Detection Model",
            version: "v2.1.0",
            status: "active",
            accuracy: 94.2,
            last_updated: 2.days.ago,
            deployment_status: "production"
          },
          {
            id: "model_002",
            name: "Formula Optimization Model",
            version: "v1.8.3",
            status: "training",
            accuracy: 89.7,
            last_updated: 6.hours.ago,
            deployment_status: "staging"
          }
        ]
      end
    end
  end
end
