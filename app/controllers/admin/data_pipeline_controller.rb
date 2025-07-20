# frozen_string_literal: true

class Admin::DataPipelineController < ApplicationController
  before_action :authenticate_admin!
  before_action :initialize_pipeline_controller

  def index
    @pipeline_status = @pipeline_controller.get_pipeline_status
    @health_check = @pipeline_controller.health_check
  end

  def start_collection
    sources = params[:sources] || DataPipeline::PipelineController::SUPPORTED_SOURCES
    sources = Array(sources)

    begin
      @pipeline_controller.start_collection(sources)

      flash[:notice] = "데이터 수집이 시작되었습니다: #{sources.join(', ')}"
      redirect_to admin_data_pipeline_index_path
    rescue => e
      flash[:alert] = "데이터 수집 시작 중 오류가 발생했습니다: #{e.message}"
      redirect_to admin_data_pipeline_index_path
    end
  end

  def stop_collection
    sources = params[:sources] || DataPipeline::PipelineController::SUPPORTED_SOURCES
    sources = Array(sources)

    begin
      @pipeline_controller.stop_collection(sources)

      flash[:notice] = "데이터 수집이 중지되었습니다: #{sources.join(', ')}"
      redirect_to admin_data_pipeline_index_path
    rescue => e
      flash[:alert] = "데이터 수집 중지 중 오류가 발생했습니다: #{e.message}"
      redirect_to admin_data_pipeline_index_path
    end
  end

  def restart_failed
    begin
      @pipeline_controller.restart_failed_sources

      flash[:notice] = "실패한 데이터 소스의 재시작을 시도했습니다."
      redirect_to admin_data_pipeline_index_path
    rescue => e
      flash[:alert] = "재시작 중 오류가 발생했습니다: #{e.message}"
      redirect_to admin_data_pipeline_index_path
    end
  end

  def health_check
    render json: @pipeline_controller.health_check
  end

  def source_status
    source = params[:source]

    if DataPipeline::PipelineController::SUPPORTED_SOURCES.include?(source)
      status = @pipeline_controller.get_pipeline_status[source]
      render json: status
    else
      render json: { error: "Unknown source: #{source}" }, status: 400
    end
  end

  private

  def initialize_pipeline_controller
    @pipeline_controller = DataPipeline::PipelineController.new
  end

  def authenticate_admin!
    redirect_to login_path unless current_user&.admin?
  end
end
