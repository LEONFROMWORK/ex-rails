# frozen_string_literal: true

module ExcelGeneration
  class GenerationController < ApplicationController
    before_action :authenticate_user!
    before_action :check_user_tokens, only: [ :from_conversation, :from_template, :large_dataset ]

    # 템플릿 기반 Excel 생성
    def from_template
      template_name = params[:template_name]
      template_data = params[:template_data] || {}
      customizations = params[:customizations] || {}

      return render_error("템플릿 이름이 필요합니다", :bad_request) unless template_name.present?

      begin
        generator = ExcelGeneration::Services::TemplateBasedGenerator.new

        result = generator.generate_from_template(
          template_name: template_name,
          template_data: template_data,
          user: current_user,
          customizations: customizations
        )

        if result[:success]
          # 생성된 파일 정보를 데이터베이스에 저장
          generated_file = save_generated_file_record(result, "template")

          render json: {
            success: true,
            file_id: generated_file.id,
            download_url: excel_generation_download_path(generated_file.id),
            file_info: {
              name: File.basename(result[:file_path]),
              size: result[:file_size],
              generation_time: result[:generation_time]
            },
            template_used: result[:template_used],
            customizations_applied: result[:customizations_applied]
          }
        else
          render_error(result[:error], :unprocessable_entity)
        end

      rescue StandardError => e
        Rails.logger.error("Template generation failed: #{e.message}")
        render_error("템플릿 기반 Excel 생성에 실패했습니다", :internal_server_error)
      end
    end

    # 대화 기반 Excel 생성
    def from_conversation
      conversation_data = params[:conversation_data]
      output_filename = params[:filename]

      return render_error("대화 데이터가 필요합니다", :bad_request) unless conversation_data.present?

      begin
        generator = ExcelGeneration::Services::TemplateBasedGenerator.new

        result = generator.generate_from_conversation(
          conversation_data: conversation_data,
          user: current_user,
          output_filename: output_filename
        )

        if result[:success]
          # 생성된 파일 정보를 데이터베이스에 저장
          generated_file = save_generated_file_record(result, "conversation")

          render json: {
            success: true,
            file_id: generated_file.id,
            download_url: excel_generation_download_path(generated_file.id),
            file_info: {
              name: File.basename(result[:file_path]),
              size: result[:file_size],
              generation_time: result[:generation_time]
            },
            requirements_analyzed: result[:requirements_analyzed],
            template_structure: result[:template_structure],
            performance_metrics: result[:performance_metrics]
          }
        else
          render_error(result[:error], :unprocessable_entity)
        end

      rescue StandardError => e
        Rails.logger.error("Conversation generation failed: #{e.message}")
        render_error("대화 기반 Excel 생성에 실패했습니다", :internal_server_error)
      end
    end

    # 대용량 데이터셋 생성
    def large_dataset
      data_source_type = params[:data_source_type] # 'database', 'api', 'csv' 등
      schema = params[:schema]
      options = params[:options] || {}

      return render_error("데이터 소스와 스키마가 필요합니다", :bad_request) unless data_source_type.present? && schema.present?

      begin
        # 데이터 소스 설정
        data_source = setup_data_source(data_source_type, params[:data_source_config])

        generator = ExcelGeneration::Services::TemplateBasedGenerator.new

        # 백그라운드 잡으로 처리 (대용량이므로)
        job = GenerateLargeDatasetJob.perform_later(
          data_source_type,
          schema,
          current_user.id,
          options
        )

        render json: {
          success: true,
          job_id: job.job_id,
          status: "processing",
          progress_url: excel_generation_progress_path(job.job_id),
          estimated_time: estimate_processing_time(data_source, schema)
        }

      rescue StandardError => e
        Rails.logger.error("Large dataset generation failed: #{e.message}")
        render_error("대용량 데이터셋 생성에 실패했습니다", :internal_server_error)
      end
    end

    # 대화형 Excel 생성 빌더 (UI 제공)
    def conversation_builder
      # 대화형 인터페이스를 위한 설정 정보 제공
      render json: {
        success: true,
        available_purposes: get_available_purposes,
        sample_conversations: get_sample_conversations,
        data_types: get_supported_data_types,
        formatting_options: get_formatting_options,
        feature_options: get_feature_options
      }
    end

    # 파일 다운로드
    def download
      file_id = params[:file_id]

      begin
        generated_file = find_generated_file(file_id)

        unless generated_file && File.exist?(generated_file.file_path)
          return render_error("파일을 찾을 수 없습니다", :not_found)
        end

        # 다운로드 통계 업데이트
        generated_file.increment!(:download_count)

        send_file generated_file.file_path,
                  filename: generated_file.original_filename,
                  type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                  disposition: "attachment"

      rescue StandardError => e
        Rails.logger.error("File download failed: #{e.message}")
        render_error("파일 다운로드에 실패했습니다", :internal_server_error)
      end
    end

    # 생성 진행률 확인
    def progress
      generation_id = params[:generation_id]

      begin
        # Sidekiq 잡 상태 확인
        job_status = check_job_status(generation_id)

        render json: {
          success: true,
          status: job_status[:status],
          progress: job_status[:progress],
          message: job_status[:message],
          estimated_remaining_time: job_status[:estimated_remaining_time],
          error: job_status[:error]
        }

      rescue StandardError => e
        Rails.logger.error("Progress check failed: #{e.message}")
        render_error("진행률 확인에 실패했습니다", :internal_server_error)
      end
    end

    private

    def save_generated_file_record(result, generation_type)
      GeneratedExcelFile.create!(
        user: current_user,
        file_path: result[:file_path],
        original_filename: File.basename(result[:file_path]),
        file_size: result[:file_size],
        generation_type: generation_type,
        generation_time: result[:generation_time],
        metadata: result[:metadata] || {},
        status: "completed"
      )
    end

    def find_generated_file(file_id)
      current_user.generated_excel_files.find_by(id: file_id)
    end

    def setup_data_source(type, config)
      case type
      when "database"
        # ActiveRecord 모델 기반 데이터 소스
        model_class = config[:model_name].constantize
        model_class.all
      when "api"
        # API 기반 데이터 소스 (구현 필요)
        raise NotImplementedError, "API data source not implemented yet"
      when "csv"
        # CSV 파일 기반 데이터 소스
        CSV.foreach(config[:csv_path], headers: true)
      else
        raise ArgumentError, "Unsupported data source type: #{type}"
      end
    end

    def estimate_processing_time(data_source, schema)
      # 데이터 크기에 따른 처리 시간 추정
      estimated_rows = case data_source
      when ActiveRecord::Relation
        data_source.count
      else
        10000 # 기본값
      end

      # 1000행당 약 1초로 추정
      (estimated_rows / 1000.0).ceil
    end

    def check_job_status(job_id)
      # Sidekiq 잡 상태 확인
      job = Sidekiq::Status::Job.new(job_id)

      {
        status: job.status,
        progress: job.progress || 0,
        message: job.message || "Processing...",
        estimated_remaining_time: job.estimated_remaining_time || nil,
        error: job.error_message
      }
    rescue StandardError
      {
        status: "unknown",
        progress: 0,
        message: "Status unavailable",
        estimated_remaining_time: nil,
        error: nil
      }
    end

    def get_available_purposes
      %w[budget inventory project sales hr academic personal general]
    end

    def get_sample_conversations
      [
        {
          purpose: "budget",
          conversation: "월별 예산 관리용 Excel을 만들어주세요. 카테고리별로 예산과 실제 지출을 비교할 수 있게 해주세요."
        },
        {
          purpose: "inventory",
          conversation: "재고 관리 시스템이 필요해요. 제품명, 재고량, 단가, 총액을 관리하고 싶습니다."
        },
        {
          purpose: "project",
          conversation: "프로젝트 일정 관리용 표를 만들어주세요. 작업명, 담당자, 시작일, 종료일, 진행상태가 필요합니다."
        }
      ]
    end

    def get_supported_data_types
      %w[text number currency date percentage email phone url]
    end

    def get_formatting_options
      %w[use_colors bold_headers auto_fit borders conditional_formatting]
    end

    def get_feature_options
      %w[charts formulas pivot_table data_validation protection multiple_sheets]
    end

    def check_user_tokens
      required_tokens = case action_name
      when "from_conversation" then 20  # AI 분석 필요
      when "from_template" then 5       # 기본 생성
      when "large_dataset" then 50      # 대용량 처리
      else 10
      end

      unless current_user.credits >= required_tokens
        render_error("토큰이 부족합니다. 이 작업을 위해서는 #{required_tokens}토큰이 필요합니다.", :payment_required)
      end
    end

    def render_error(message, status)
      render json: {
        success: false,
        error: message
      }, status: status
    end
  end
end
