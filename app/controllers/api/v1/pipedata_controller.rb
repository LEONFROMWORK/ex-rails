# frozen_string_literal: true

# PipeData → ExcelApp-Rails 데이터 수신 컨트롤러
class Api::V1::PipedataController < Api::V1::BaseController
  skip_before_action :authenticate_user!
  before_action :authenticate_pipedata_token

  # POST /api/v1/pipedata
  # PipeData에서 전송하는 Q&A 데이터를 수신하고 저장
  def create
    result = PipedataIngestionService.call(pipedata_params)

    if result.success?
      render json: {
        success: true,
        processed: result.data[:processed],
        created: result.data[:created],
        duplicates: result.data[:duplicates],
        errors: result.data[:errors],
        message: result.data[:message]
      }, status: :ok
    else
      render json: {
        success: false,
        error: result.error,
        details: result.error_details
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "PipeData ingestion error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      success: false,
      error: "Internal server error",
      message: "Failed to process PipeData"
    }, status: :internal_server_error
  end

  # GET /api/v1/pipedata
  # 동기화 상태 및 통계 반환
  def show
    stats = KnowledgeItemStatsService.call

    render json: {
      total_records: stats[:total_count],
      average_quality: stats[:average_quality],
      last_sync: stats[:last_created],
      sources: stats[:source_distribution],
      status: "active",
      rails_version: Rails.version,
      app_version: "1.0.0"
    }
  rescue StandardError => e
    Rails.logger.error "PipeData stats error: #{e.message}"

    render json: {
      error: "Internal server error",
      message: "Failed to retrieve stats"
    }, status: :internal_server_error
  end

  private

  def authenticate_pipedata_token
    token = request.headers["X-PipeData-Token"]
    expected_token = Rails.application.credentials.pipedata_api_token ||
                     ENV["PIPEDATA_API_TOKEN"]

    unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected_token)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def pipedata_params
    data = params[:data]
    return [] unless data.is_a?(Array)

    data.map do |item|
      item.permit(
        :question, :answer, :difficulty, :quality_score, :source,
        excel_functions: [], code_snippets: [], tags: [],
        metadata: {}
      )
    end
  end
end
