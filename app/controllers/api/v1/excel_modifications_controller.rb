# frozen_string_literal: true

module Api
  module V1
    # API controller for Excel file modifications with AI assistance
    class ExcelModificationsController < Api::V1::BaseController
      before_action :authenticate_user!
      before_action :set_excel_file, only: [ :modify ]

      # GET /api/v1/excel_modifications/recommend_tier
      # Recommend optimal AI tier based on context
      def recommend_tier
        excel_file = current_user.excel_files.find_by(id: params[:file_id])

        unless excel_file
          return render json: {
            success: false,
            error: "Excel file not found"
          }, status: :not_found
        end

        # Create a temporary handler to get tier recommendation
        handler = ExcelModification::Handlers::ModifyExcelHandler.new(
          excel_file: excel_file,
          screenshot: "temp",
          user_request: params[:request] || "",
          user: current_user
        )

        # Get recommendation
        recommended_tier = handler.send(:recommend_optimal_tier)
        available_tiers = handler.send(:available_tiers_for_user)

        # Get credit costs
        tier_costs = {
          speed: { base: 30, estimated: handler.send(:estimate_required_credits_for_tier, :speed) },
          balanced: { base: 50, estimated: handler.send(:estimate_required_credits_for_tier, :balanced) },
          quality: { base: 100, estimated: handler.send(:estimate_required_credits_for_tier, :quality) }
        }

        render json: {
          success: true,
          data: {
            recommended_tier: recommended_tier,
            available_tiers: available_tiers,
            tier_costs: tier_costs,
            user_credits: current_user.credits,
            reasons: get_recommendation_reasons(recommended_tier, excel_file, params[:request])
          }
        }
      end

      # POST /api/v1/excel_modifications/modify
      # Modify Excel file based on screenshot and user request
      def modify
        # Parse screenshot data
        screenshot_data = parse_image_data(params[:screenshot])

        if screenshot_data.nil?
          return render json: {
            success: false,
            error: "Invalid or missing screenshot data"
          }, status: :bad_request
        end

        # Execute modification handler
        handler = ExcelModification::Handlers::ModifyExcelHandler.new(
          excel_file: @excel_file,
          screenshot: screenshot_data,
          user_request: params[:request],
          user: current_user,
          tier: params[:tier]
        )

        result = handler.execute

        if result.success?
          render json: {
            success: true,
            data: {
              modified_file: {
                id: result.value[:modified_file].id,
                filename: result.value[:modified_file].original_name,
                size: result.value[:modified_file].file_size,
                created_at: result.value[:modified_file].created_at
              },
              modifications: result.value[:modifications],
              download_url: result.value[:download_url],
              preview: result.value[:preview],
              credits_used: result.value[:credits_used]
            }
          }
        else
          # Determine appropriate HTTP status based on error type
          status = case result.error
          when CommonErrors::ValidationError
            :bad_request
          when CommonErrors::AuthorizationError
            :forbidden
          when CommonErrors::InsufficientCreditsError
            :payment_required
          else
            :unprocessable_entity
          end

          # Extract error message and details
          error_message = if result.error.respond_to?(:message)
            result.error.message
          else
            result.error.to_s
          end

          error_details = if result.error.respond_to?(:details)
            result.error.details
          else
            {}
          end

          render json: {
            success: false,
            error: error_message,
            details: error_details,
            error_type: result.error.class.name.demodulize,
            quality_feedback: error_details[:quality_feedback]
          }, status: status
        end
      end

      # POST /api/v1/excel_modifications/convert_to_formula
      # Convert natural language to Excel formula
      def convert_to_formula
        converter = ExcelModification::Services::AiToFormulaConverter.new

        result = converter.convert(
          params[:text],
          {
            worksheet_name: params[:worksheet],
            selected_cell: params[:cell],
            data_range: params[:range],
            screenshot: parse_image_data(params[:screenshot])
          }
        )

        if result.success?
          render json: {
            success: true,
            data: result.value
          }
        else
          render json: {
            success: false,
            error: result.error
          }, status: :unprocessable_entity
        end
      end

      private

      def set_excel_file
        @excel_file = current_user.excel_files.find_by(id: params[:file_id])

        unless @excel_file
          render json: {
            success: false,
            error: "Excel file not found"
          }, status: :not_found
        end
      end

      def get_recommendation_reasons(tier, excel_file, request)
        reasons = []
        file_size_mb = excel_file.file_size / 1.megabyte.to_f

        case tier
        when :speed
          reasons << "빠른 처리가 가능합니다"
          reasons << "크레딧을 절약할 수 있습니다" if current_user.credits < 100
          reasons << "간단한 수정에 적합합니다" if request && request.length < 50
        when :balanced
          reasons << "가장 균형잡힌 선택입니다"
          reasons << "대부분의 수정 작업에 최적화되어 있습니다"
          reasons << "비용 대비 효과가 좋습니다"
        when :quality
          reasons << "가장 정밀한 분석을 제공합니다"
          reasons << "복잡한 수정 작업에 적합합니다" if request && request.length > 200
          reasons << "대용량 파일 처리에 최적화되어 있습니다" if file_size_mb > 5
        end

        reasons
      end

      def parse_image_data(image_param)
        return nil if image_param.blank?

        # Handle base64 encoded image
        if image_param.is_a?(String) && image_param.match?(/^data:image/)
          # Extract base64 data
          base64_data = image_param.split(",")[1]
          Base64.decode64(base64_data)
        elsif image_param.respond_to?(:read)
          # Handle uploaded file
          image_param.read
        else
          nil
        end
      rescue StandardError => e
        Rails.logger.error("Failed to parse image data: #{e.message}")
        nil
      end
    end
  end
end
