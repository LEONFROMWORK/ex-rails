# frozen_string_literal: true

module Api
  module V1
    class AiController < Api::V1::BaseController
      before_action :authenticate_user!

      def chat
        handler = AiIntegration::Handlers::ChatHandler.new(
          user: current_user,
          message: params[:message],
          conversation_id: params[:conversation_id],
          file_id: params[:file_id]
        )

        result = handler.execute

        if result.success?
          render json: {
            response: result.value[:response],
            conversation_id: result.value[:conversation_id],
            credits_used: result.value[:credits_used],
            ai_tier_used: result.value[:ai_tier_used],
            confidence_score: result.value[:confidence_score]
          }
        else
          render json: {
            error: result.error.message
          }, status: :unprocessable_entity
        end
      end

      def feedback
        handler = AiIntegration::Handlers::FeedbackHandler.new(
          user: current_user,
          conversation_id: params[:conversation_id],
          message_id: params[:message_id],
          rating: params[:rating],
          feedback_text: params[:feedback_text]
        )

        result = handler.execute

        if result.success?
          render json: { message: "Feedback submitted successfully" }
        else
          render json: {
            error: result.error.message
          }, status: :unprocessable_entity
        end
      end

      def analyze_image
        unless params[:image].present?
          render json: { error: "Image file is required" }, status: :bad_request
          return
        end

        unless params[:description].present?
          render json: { error: "Description is required" }, status: :bad_request
          return
        end

        # Use new domain-driven command
        command = AiIntegration::Commands::AnalyzeImage.new.tap do |cmd|
          cmd.image_data = params[:image].read
          cmd.prompt = params[:description]
          cmd.user_id = current_user.id
          cmd.analysis_type = params[:analysis_type] || "general"
          cmd.tier = determine_multimodal_tier(current_user, params[:analysis_type])
          cmd.options = {
            conversation_history: params[:conversation_history] || [],
            template_type: params[:template_type],
            custom_questions: params[:custom_questions] || [],
            temperature: params[:temperature]&.to_f || 0.4
          }
        end

        result = command.call

        if result.success?
          render json: {
            success: true,
            analysis: result.value[:content],
            structured_analysis: result.value[:structured_analysis],
            confidence_score: result.value[:confidence_score],
            credits_used: result.value[:credits_used],
            cost: result.value[:cost],
            provider: result.value[:provider],
            model: result.value[:model],
            tier: result.value[:tier],
            analysis_type: result.value[:analysis_type]
          }
        else
          render json: {
            success: false,
            error: result.error
          }, status: :unprocessable_entity
        end
      end

      def analyze_vba
        unless params[:file_id].present?
          render json: { error: "File ID is required" }, status: :bad_request
          return
        end

        file = current_user.excel_files.find_by(id: params[:file_id])
        unless file
          render json: { error: "File not found" }, status: :not_found
          return
        end

        begin
          vba_service = ExcelAnalysis::Services::VbaAnalysisService.new(
            file.file_path,
            deep_analysis: params[:deep_analysis] == "true",
            security_scan: params[:security_scan] == "true",
            performance_analysis: params[:performance_analysis] == "true"
          )

          result = vba_service.analyze_vba_comprehensive

          if result[:success]
            render json: {
              success: true,
              modules_found: result[:modules_found],
              static_analysis: result[:static_analysis],
              security_analysis: result[:security_analysis],
              performance_analysis: result[:performance_analysis],
              complexity_analysis: result[:complexity_analysis],
              overall_score: result[:overall_score],
              recommendations: result[:recommendations],
              processing_time: result[:processing_time]
            }
          else
            render json: { error: result[:error] }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("VBA analysis failed: #{e.message}")
          render json: { error: "VBA analysis failed" }, status: :internal_server_error
        end
      end

      def generate_template
        unless params[:template_name].present?
          render json: { error: "Template name is required" }, status: :bad_request
          return
        end

        unless params[:template_data].present?
          render json: { error: "Template data is required" }, status: :bad_request
          return
        end

        begin
          template_service = ExcelGeneration::Services::TemplateBasedGenerator.new

          result = template_service.generate_from_template(
            template_name: params[:template_name],
            template_data: params[:template_data],
            user: current_user,
            customizations: params[:customizations] || {}
          )

          if result[:success]
            render json: {
              success: true,
              file_path: result[:file_path],
              file_size: result[:file_size],
              generation_time: result[:generation_time],
              template_used: result[:template_used],
              customizations_applied: result[:customizations_applied],
              download_url: api_v1_file_download_path(result[:metadata][:id])
            }
          else
            render json: { error: result[:error] }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Template generation failed: #{e.message}")
          render json: { error: "Template generation failed" }, status: :internal_server_error
        end
      end

      def create_from_conversation
        unless params[:conversation_data].present?
          render json: { error: "Conversation data is required" }, status: :bad_request
          return
        end

        begin
          template_service = ExcelGeneration::Services::TemplateBasedGenerator.new

          result = template_service.generate_from_conversation(
            conversation_data: params[:conversation_data],
            user: current_user,
            output_filename: params[:filename]
          )

          if result[:success]
            render json: {
              success: true,
              file_path: result[:file_path],
              file_size: result[:file_size],
              generation_time: result[:generation_time],
              template_structure: result[:template_structure],
              requirements_analyzed: result[:requirements_analyzed],
              performance_metrics: result[:performance_metrics],
              download_url: api_v1_file_download_path(result[:metadata][:id])
            }
          else
            render json: { error: result[:error] }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("Conversation-based Excel generation failed: #{e.message}")
          render json: { error: "Excel generation from conversation failed" }, status: :internal_server_error
        end
      end

      private

      def determine_multimodal_tier(user, analysis_type)
        # 사용자 등급과 분석 타입에 따른 모델 티어 결정
        case user.subscription_tier
        when "enterprise"
          # 엔터프라이즈: 분석 타입에 관계없이 프리미엄 모델
          :premium
        when "pro"
          # 프로: 복잡한 분석은 프리미엄, 일반적인 분석은 밸런스드
          complex_analysis_types = %w[formula_analysis data_validation template]
          complex_analysis_types.include?(analysis_type) ? :premium : :balanced
        else
          # 무료/베이직: 비용 효율적인 모델
          :cost_effective
        end
      end
    end
  end
end
