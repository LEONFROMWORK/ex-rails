# frozen_string_literal: true

module ExcelModification
  module Handlers
    # Handler for modifying Excel files based on AI suggestions
    # Follows the established architecture pattern with BaseHandler
    class ModifyExcelHandler < Common::BaseHandler
      def initialize(excel_file:, screenshot:, user_request:, user:, tier: nil)
        @excel_file = excel_file
        @screenshot = screenshot
        @user_request = user_request
        @user = user
        @tier = determine_tier(tier)
      end

      def execute
        # Validate inputs
        validation_result = validate_inputs
        return validation_result if validation_result.failure?

        # Check user permissions
        permission_result = check_permissions
        return permission_result if permission_result.failure?

        # Check user credits
        credits_result = check_credits
        return credits_result if credits_result.failure?

        # Perform modification
        modification_service = ExcelModification::Services::ExcelModificationService.new
        result = modification_service.modify_with_ai_suggestions(
          excel_file: @excel_file,
          screenshot: @screenshot,
          user_request: @user_request,
          user: @user,
          tier: @tier
        )

        return result if result.failure?

        # Deduct credits
        deduct_credits(calculate_credits_used(result.value))

        # Log activity
        log_modification_activity(result.value)

        # Return success with all necessary data
        success({
          modified_file: result.value[:modified_file],
          modifications: result.value[:modifications_applied],
          download_url: result.value[:download_url],
          preview: result.value[:preview],
          credits_used: calculate_credits_used(result.value)
        })

      rescue StandardError => e
        Rails.logger.error("Excel modification handler error: #{e.message}")
        failure("Failed to process Excel modification: #{e.message}")
      end

      private

      def validate_inputs
        errors = []

        errors << "Excel file not found" unless @excel_file
        errors << "Screenshot is required" if @screenshot.blank?
        errors << "User request cannot be blank" if @user_request.blank?
        errors << "User not found" unless @user

        return success if errors.empty?

        failure(
          CommonErrors::ValidationError.new(
            message: "Validation failed",
            details: { errors: errors }
          )
        )
      end

      def check_permissions
        unless @excel_file.user_id == @user.id || @user.admin?
          return failure(
            CommonErrors::AuthorizationError.new(
              message: "You don't have permission to modify this file"
            )
          )
        end

        success
      end

      def check_credits
        return success unless Rails.application.config.features[:subscription_required]

        required_credits = estimate_required_credits

        if @user.credits < required_credits
          return failure(
            CommonErrors::InsufficientCreditsError.new(
              required: required_credits,
              available: @user.credits
            )
          )
        end

        success
      end

      def estimate_required_credits
        # Base cost depends on tier
        base_cost = case @tier
        when :speed then 30
        when :balanced then 50
        when :quality then 100
        else 50
        end

        # Additional cost based on file size
        size_cost = (@excel_file.file_size / 1.megabyte.to_f * 10).ceil

        # Additional cost for complex requests
        complexity_cost = @user_request.length > 200 ? 20 : 0

        base_cost + size_cost + complexity_cost
      end

      def calculate_credits_used(result)
        # Base cost based on tier
        credits = case @tier
        when :speed then 30
        when :balanced then 50
        when :quality then 100
        else 50
        end

        # Additional cost per modification
        credits += result[:modifications_applied].size * 5

        # Cap at maximum based on tier
        max_credits = case @tier
        when :speed then 100
        when :balanced then 200
        when :quality then 300
        else 200
        end

        [ credits, max_credits ].min
      end

      def deduct_credits(amount)
        @user.consume_credits!(amount)
      rescue StandardError => e
        Rails.logger.error("Failed to deduct credits: #{e.message}")
      end

      def log_modification_activity(result)
        # Log activity if activity tracking is implemented
        Rails.logger.info("Excel modification completed for user #{@user.id}, file #{@excel_file.id}")
        Rails.logger.info("Modifications applied: #{result[:modifications_applied]&.size || 0}")
        Rails.logger.info("AI tier used: #{@tier}")
      rescue StandardError => e
        Rails.logger.error("Failed to log activity: #{e.message}")
      end

      def determine_tier(requested_tier)
        # If tier is explicitly requested and available, use it
        if requested_tier
          available_tiers = available_tiers_for_user
          return requested_tier.to_sym if available_tiers.include?(requested_tier.to_sym)
        end

        # Otherwise, recommend optimal tier
        recommend_optimal_tier
      end

      def recommend_optimal_tier
        # Analyze various factors to recommend the best tier
        file_size_mb = @excel_file.file_size / 1.megabyte.to_f
        request_complexity = analyze_request_complexity
        user_credits = @user.credits
        user_tier = @user.tier

        # For small files with simple requests
        if file_size_mb < 1 && request_complexity == :simple && user_credits < 100
          return :speed
        end

        # For Pro/Enterprise users with sufficient credits and complex requests
        if (user_tier == "pro" || user_tier == "enterprise") &&
           user_credits >= 150 &&
           (request_complexity == :complex || file_size_mb > 5)
          return :quality
        end

        # For most cases, balanced is optimal
        if user_credits >= 50
          return :balanced
        end

        # Fallback to speed if low on credits
        :speed
      end

      def analyze_request_complexity
        # Simple heuristic based on request content
        request_lower = @user_request.downcase

        # Complex indicators
        complex_keywords = [
          "복잡한", "정밀한", "상세한", "분석", "검증",
          "complex", "detailed", "analyze", "validate",
          "여러", "다수", "전체", "multiple", "entire"
        ]

        # Simple indicators
        simple_keywords = [
          "간단한", "빠른", "기본",
          "simple", "quick", "basic",
          "하나", "단순", "single"
        ]

        complex_count = complex_keywords.count { |word| request_lower.include?(word) }
        simple_count = simple_keywords.count { |word| request_lower.include?(word) }

        # Also consider request length
        if @user_request.length > 200 || complex_count > 1
          :complex
        elsif simple_count > 0 || @user_request.length < 50
          :simple
        else
          :moderate
        end
      end

      def available_tiers_for_user
        return [ :speed, :balanced, :quality ] unless Rails.application.config.features[:subscription_required]

        tiers = [ :speed ]

        if @user.credits >= 50
          tiers << :balanced
        end

        if @user.credits >= 100 && (@user.pro? || @user.enterprise?)
          tiers << :quality
        end

        tiers
      end

      def estimate_required_credits_for_tier(tier)
        original_tier = @tier
        @tier = tier
        credits = estimate_required_credits
        @tier = original_tier
        credits
      end

      def generate_quality_feedback(quality_result)
        if quality_result.error.message.include?("resolution")
          {
            type: "low_resolution",
            suggestion: "더 높은 해상도로 스크린샷을 다시 캡처해 주세요. Excel 내용이 명확하게 보이도록 해주세요.",
            tips: [
              "전체 화면 캡처 대신 필요한 부분만 캡처하세요",
              "Excel을 확대(Zoom)하여 텍스트가 잘 보이도록 하세요",
              "Windows: Win+Shift+S / Mac: Cmd+Shift+4 사용을 권장합니다"
            ]
          }
        elsif quality_result.error.message.include?("too small")
          {
            type: "file_too_small",
            suggestion: "스크린샷이 너무 작습니다. 더 선명한 이미지를 업로드해 주세요.",
            tips: [
              "PNG 형식으로 저장하면 더 좋은 품질을 얻을 수 있습니다",
              "압축률이 낮은 형식을 사용하세요"
            ]
          }
        else
          {
            type: "general_quality",
            suggestion: quality_result.error.message,
            tips: [
              "화면이 흐릿하지 않은지 확인하세요",
              "Excel 내용이 명확하게 보이는지 확인하세요",
              "필요한 부분이 모두 포함되었는지 확인하세요"
            ]
          }
        end
      end
    end
  end
end
