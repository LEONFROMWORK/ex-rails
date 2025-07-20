# frozen_string_literal: true

module AiIntegration
  module MultiProvider
    class ThreeTierManager
      # Quality thresholds for tier escalation
      TIER1_THRESHOLD = 0.75
      TIER2_THRESHOLD = 0.85
      TIER3_THRESHOLD = 0.95

      # Token cost multipliers
      TIER1_COST_MULTIPLIER = 1.0
      TIER2_COST_MULTIPLIER = 2.6   # 2.6x more expensive than tier1
      TIER3_COST_MULTIPLIER = 10.0  # 10x more expensive than tier1

      def initialize(user:)
        @user = user
      end

      def analyze_excel_with_intelligence(errors:, file_metadata:, images: nil)
        Rails.logger.info("Starting intelligent 3-tier AI analysis for user #{@user.id}")

        # Step 1: Analyze complexity and determine optimal tier
        optimal_tier = determine_optimal_tier(errors, file_metadata, images)

        # Step 2: Start with the determined tier
        result = perform_tier_analysis(optimal_tier, errors, file_metadata, images)

        if result.success?
          # Step 3: Check if escalation is needed based on quality
          final_result = check_and_escalate_if_needed(result.value, errors, file_metadata, images, optimal_tier)
          final_result
        else
          # Step 4: If optimal tier fails, try lower tiers
          fallback_analysis(errors, file_metadata, images, optimal_tier)
        end
      end

      private

      def determine_optimal_tier(errors, file_metadata, images)
        complexity_score = calculate_complexity_score(errors, file_metadata, images)

        # Determine tier based on complexity and user subscription
        if complexity_score >= 0.8 && @user.enterprise?
          "tier3"
        elsif complexity_score >= 0.5 && (@user.pro? || @user.enterprise?)
          "tier2"
        else
          "tier1"
        end
      end

      def calculate_complexity_score(errors, file_metadata, images)
        score = 0.0

        # Error complexity analysis
        error_complexity = analyze_error_complexity(errors)
        score += error_complexity * 0.4

        # File complexity analysis
        file_complexity = analyze_file_complexity(file_metadata)
        score += file_complexity * 0.3

        # Image complexity (multimodal processing)
        image_complexity = images&.any? ? 0.3 : 0.0
        score += image_complexity * 0.2

        # User tier bonus (higher tier users get more complex analysis)
        user_tier_bonus = case @user.tier
        when "enterprise" then 0.1
        when "pro" then 0.05
        else 0.0
        end
        score += user_tier_bonus

        # Normalize to 0-1 scale
        [ score, 1.0 ].min
      end

      def analyze_error_complexity(errors)
        return 0.0 if errors.empty?

        complexity_weights = {
          "circular_reference" => 0.9,
          "complex_formula_error" => 0.8,
          "data_integrity_issue" => 0.7,
          "macro_error" => 0.8,
          "external_reference_error" => 0.6,
          "formula_error" => 0.4,
          "data_validation" => 0.3,
          "format_error" => 0.2
        }

        severity_weights = {
          "critical" => 1.0,
          "high" => 0.8,
          "medium" => 0.5,
          "low" => 0.2
        }

        total_weight = 0.0
        errors.each do |error|
          type_weight = complexity_weights[error[:type]] || 0.3
          severity_weight = severity_weights[error[:severity]] || 0.3
          total_weight += type_weight * severity_weight
        end

        # Average complexity
        total_weight / errors.size
      end

      def analyze_file_complexity(file_metadata)
        complexity = 0.0

        # File size factor
        file_size = file_metadata[:file_size] || 0
        complexity += [ file_size / 1_000_000.0, 0.3 ].min  # Up to 0.3 for large files

        # Worksheet count
        sheet_count = file_metadata[:sheet_count] || 1
        complexity += [ sheet_count / 20.0, 0.2 ].min  # Up to 0.2 for many sheets

        # Formula complexity
        formula_count = file_metadata[:formula_count] || 0
        complexity += [ formula_count / 100.0, 0.3 ].min  # Up to 0.3 for many formulas

        # External references
        external_refs = file_metadata[:external_references] || 0
        complexity += [ external_refs / 10.0, 0.2 ].min  # Up to 0.2 for external refs

        complexity
      end

      def perform_tier_analysis(tier, errors, file_metadata, images)
        validate_tier_access(tier)

        ai_service = AiAnalysisService.new(primary_provider: "openrouter")

        result = ai_service.analyze_errors(
          errors: errors,
          file_metadata: file_metadata,
          tier: tier,
          user: @user,
          images: images
        )

        if result.success?
          # Calculate and deduct tokens
          credits_used = result.value[:credits_used] || 0
          token_cost = calculate_token_cost(credits_used, tier)
          @user.consume_tokens!(token_cost)

          # Add tier metadata
          result.value[:tier_used] = tier
          result.value[:token_cost] = token_cost
          result.value[:analysis_timestamp] = Time.current.iso8601

          Rails.logger.info("#{tier.upcase} analysis completed. Tokens used: #{credits_used}, Cost: #{token_cost}")
        end

        result
      end

      def check_and_escalate_if_needed(result, errors, file_metadata, images, current_tier)
        confidence = result[:overall_confidence] || 0.0

        # Determine if escalation is needed
        should_escalate = case current_tier
        when "tier1"
                           confidence < TIER1_THRESHOLD && can_escalate_to_tier2?
        when "tier2"
                           confidence < TIER2_THRESHOLD && can_escalate_to_tier3?
        else
                           false
        end

        if should_escalate
          next_tier = current_tier == "tier1" ? "tier2" : "tier3"
          Rails.logger.info("Escalating from #{current_tier} to #{next_tier} due to low confidence: #{confidence}")

          escalated_result = perform_tier_analysis(next_tier, errors, file_metadata, images)

          if escalated_result.success?
            # Merge results from both tiers
            merged_result = merge_tier_results(result, escalated_result.value, current_tier, next_tier)
            Common::Result.success(merged_result)
          else
            # Escalation failed, return original result
            result[:escalation_attempted] = true
            result[:escalation_failed] = true
            Common::Result.success(result)
          end
        else
          # No escalation needed
          result[:escalation_needed] = false
          Common::Result.success(result)
        end
      end

      def fallback_analysis(errors, file_metadata, images, failed_tier)
        Rails.logger.warn("#{failed_tier.upcase} analysis failed, attempting fallback")

        # Try tiers in descending order
        fallback_tiers = case failed_tier
        when "tier3" then [ "tier2", "tier1" ]
        when "tier2" then [ "tier1" ]
        else []
        end

        fallback_tiers.each do |tier|
          next unless can_access_tier?(tier)

          result = perform_tier_analysis(tier, errors, file_metadata, images)
          if result.success?
            result.value[:fallback_from] = failed_tier
            result.value[:fallback_reason] = "#{failed_tier.upcase} analysis failed"
            return result
          end
        end

        # All tiers failed
        Common::Result.failure(
          Common::Errors::AIProviderError.new(
            provider: "all_tiers",
            message: "All tier analysis attempts failed"
          )
        )
      end

      def merge_tier_results(lower_result, higher_result, lower_tier, higher_tier)
        {
          # Use higher tier results as primary
          analysis: higher_result[:analysis],
          corrections: higher_result[:corrections],
          overall_confidence: higher_result[:overall_confidence],
          summary: higher_result[:summary],
          estimated_time_saved: higher_result[:estimated_time_saved],

          # Tier comparison data
          "#{lower_tier}_confidence": lower_result[:overall_confidence],
          "#{higher_tier}_confidence": higher_result[:overall_confidence],
          confidence_improvement: higher_result[:overall_confidence] - lower_result[:overall_confidence],

          # Token usage
          "#{lower_tier}_credits_used": lower_result[:credits_used],
          "#{higher_tier}_credits_used": higher_result[:credits_used],
          total_credits_used: lower_result[:credits_used] + higher_result[:credits_used],

          # Cost tracking
          "#{lower_tier}_cost": lower_result[:token_cost],
          "#{higher_tier}_cost": higher_result[:token_cost],
          total_cost: lower_result[:token_cost] + higher_result[:token_cost],

          # Metadata
          tier_used: higher_tier,
          escalated_from: lower_tier,
          escalation_reason: "Low confidence (#{lower_result[:overall_confidence]&.round(2)})",
          analysis_timestamp: Time.current.iso8601
        }
      end

      def validate_tier_access(tier)
        required_credits = estimate_tier_cost(tier)

        unless @user.credits >= required_credits
          raise Common::Errors::InsufficientCreditsError.new(
            message: "Insufficient credits for #{tier.upcase} analysis",
            required_credits: required_credits,
            current_credits: @user.credits
          )
        end

        case tier
        when "tier3"
          unless @user.enterprise?
            raise Common::Errors::AuthorizationError.new(
              message: "Tier 3 analysis requires ENTERPRISE subscription"
            )
          end
        when "tier2"
          unless @user.pro? || @user.enterprise?
            raise Common::Errors::AuthorizationError.new(
              message: "Tier 2 analysis requires PRO or ENTERPRISE subscription"
            )
          end
        end
      end

      def can_escalate_to_tier2?
        @user.credits >= estimate_tier_cost("tier2") && (@user.pro? || @user.enterprise?)
      end

      def can_escalate_to_tier3?
        @user.credits >= estimate_tier_cost("tier3") && @user.enterprise?
      end

      def can_access_tier?(tier)
        case tier
        when "tier3"
          @user.enterprise? && @user.credits >= estimate_tier_cost("tier3")
        when "tier2"
          (@user.pro? || @user.enterprise?) && @user.credits >= estimate_tier_cost("tier2")
        else
          @user.credits >= estimate_tier_cost("tier1")
        end
      end

      def estimate_tier_cost(tier)
        base_cost = case tier
        when "tier3" then 100
        when "tier2" then 50
        else 10
        end

        base_cost
      end

      def calculate_token_cost(credits_used, tier)
        # Base cost calculation
        base_cost = (credits_used / 100.0).ceil

        # Apply tier multiplier
        multiplier = case tier
        when "tier3" then TIER3_COST_MULTIPLIER
        when "tier2" then TIER2_COST_MULTIPLIER
        else TIER1_COST_MULTIPLIER
        end

        (base_cost * multiplier).ceil
      end
    end
  end
end
