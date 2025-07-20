# frozen_string_literal: true

module ExcelAnalysis
  class ImageAnalysisController < ApplicationController
    before_action :authenticate_user!
    before_action :check_user_tokens, only: [ :analyze, :analyze_chart, :analyze_formula, :analyze_video ]

    # 일반 이미지 분석
    def analyze
      return render_error("이미지 파일이 필요합니다", :bad_request) unless image_present?

      begin
        gemini_service = AiIntegration::Services::GeminiMultimodalService.new

        result = gemini_service.analyze_image_with_context(
          image_data: extract_image_data,
          text_prompt: params[:prompt] || "Excel 관련 이미지를 분석해주세요.",
          user: current_user,
          context: { analysis_type: "general" }
        )

        if result[:analysis]
          render json: {
            success: true,
            analysis: result[:analysis],
            confidence_score: result[:confidence_score],
            credits_used: result[:credits_used],
            cost_saved: result[:cost_saved],
            processing_time: result[:processing_time]
          }
        else
          render_error("이미지 분석에 실패했습니다", :unprocessable_entity)
        end

      rescue StandardError => e
        Rails.logger.error("Image analysis failed: #{e.message}")
        render_error("이미지 분석 중 오류가 발생했습니다", :internal_server_error)
      end
    end

    # 차트/그래프 특화 분석
    def analyze_chart
      return render_error("차트 이미지가 필요합니다", :bad_request) unless image_present?

      begin
        gemini_service = AiIntegration::Services::GeminiMultimodalService.new

        result = gemini_service.analyze_excel_visualization(
          image_data: extract_image_data,
          analysis_type: "chart_analysis",
          user: current_user
        )

        render json: {
          success: true,
          chart_analysis: result[:analysis],
          chart_improvements: result[:chart_improvements],
          data_quality_score: result[:data_quality_score],
          confidence_score: result[:confidence_score],
          credits_used: result[:credits_used]
        }

      rescue StandardError => e
        Rails.logger.error("Chart analysis failed: #{e.message}")
        render_error("차트 분석 중 오류가 발생했습니다", :internal_server_error)
      end
    end

    # 수식 스크린샷 분석
    def analyze_formula
      return render_error("수식 스크린샷이 필요합니다", :bad_request) unless image_present?

      begin
        gemini_service = AiIntegration::Services::GeminiMultimodalService.new

        result = gemini_service.analyze_excel_visualization(
          image_data: extract_image_data,
          analysis_type: "formula_visualization",
          user: current_user
        )

        render json: {
          success: true,
          formula_analysis: result[:analysis],
          formula_complexity: result[:formula_complexity],
          optimization_suggestions: result[:optimization_suggestions],
          confidence_score: result[:confidence_score],
          credits_used: result[:credits_used]
        }

      rescue StandardError => e
        Rails.logger.error("Formula analysis failed: #{e.message}")
        render_error("수식 분석 중 오류가 발생했습니다", :internal_server_error)
      end
    end

    # 비디오 튜토리얼 분석 (Gemini 고유 기능)
    def analyze_video
      return render_error("비디오 파일이 필요합니다", :bad_request) unless video_present?

      begin
        gemini_service = AiIntegration::Services::GeminiMultimodalService.new

        video_data = extract_video_data
        duration = params[:duration]&.to_i

        result = gemini_service.analyze_excel_tutorial_video(
          video_data: video_data,
          user: current_user,
          duration_seconds: duration
        )

        if result[:error]
          render_error(result[:message], :unprocessable_entity)
        else
          render json: {
            success: true,
            tutorial_analysis: result[:tutorial_analysis],
            key_steps: result[:key_steps],
            excel_functions: result[:excel_functions],
            difficulty_level: result[:difficulty_level],
            credits_used: result[:credits_used],
            processing_time: result[:processing_time]
          }
        end

      rescue StandardError => e
        Rails.logger.error("Video analysis failed: #{e.message}")
        render_error("비디오 분석 중 오류가 발생했습니다", :internal_server_error)
      end
    end

    private

    def image_present?
      params[:image].present?
    end

    def video_present?
      params[:video].present?
    end

    def extract_image_data
      if params[:image].respond_to?(:read)
        params[:image].read
      elsif params[:image].is_a?(String)
        # Base64 encoded image
        Base64.decode64(params[:image])
      else
        params[:image]
      end
    end

    def extract_video_data
      if params[:video].respond_to?(:read)
        params[:video].read
      elsif params[:video].is_a?(String)
        # Base64 encoded video
        Base64.decode64(params[:video])
      else
        params[:video]
      end
    end

    def check_user_tokens
      unless current_user.credits >= 10 # 멀티모달 분석은 10토큰 소모
        render_error("토큰이 부족합니다. 멀티모달 분석을 위해서는 최소 10토큰이 필요합니다.", :payment_required)
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
