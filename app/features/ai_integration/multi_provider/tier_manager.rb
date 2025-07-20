# frozen_string_literal: true

module AiIntegration
  module MultiProvider
    class TierManager
      CONFIDENCE_THRESHOLD = 0.85
      MAX_TIER1_TOKENS = 1000
      MAX_TIER2_TOKENS = 2000

      def initialize(user:)
        @user = user
      end

      def analyze_excel(file_data, errors:, file_metadata:)
        Rails.logger.info("Starting 2-tier AI analysis for user #{@user.id}")

        # Step 1: Tier 1 Analysis
        tier1_result = perform_tier1_analysis(file_data, errors, file_metadata)

        if tier1_result.failure?
          Rails.logger.error("Tier 1 analysis failed: #{tier1_result.error}")
          return tier1_result
        end

        # Step 2: Check if escalation to Tier 2 is needed
        if should_escalate_to_tier2?(tier1_result.value, errors)
          Rails.logger.info("Escalating to Tier 2 analysis (confidence: #{tier1_result.value[:overall_confidence]})")
          return perform_tier2_analysis(file_data, errors, file_metadata, tier1_result.value)
        end

        # Step 3: Return Tier 1 result with tier info
        tier1_result.value[:tier_used] = "tier1"
        tier1_result.value[:escalation_reason] = "Not needed - confidence above threshold"

        Common::Result.success(tier1_result.value)
      end

      private

      def perform_tier1_analysis(file_data, errors, file_metadata)
        validate_tier1_access

        ai_service = AiAnalysisService.new(primary_provider: "openai")

        result = ai_service.analyze_errors(
          errors: errors,
          file_metadata: file_metadata,
          tier: "tier1",
          user: @user
        )

        if result.success?
          # Deduct Tier 1 tokens
          @user.consume_tokens!(calculate_tier1_cost(result.value[:credits_used]))
          Rails.logger.info("Tier 1 analysis completed. Tokens used: #{result.value[:credits_used]}")
        end

        result
      end

      def perform_tier2_analysis(file_data, errors, file_metadata, tier1_result)
        validate_tier2_access

        ai_service = AiAnalysisService.new(primary_provider: "anthropic")

        # Enhanced context for Tier 2
        enhanced_context = build_tier2_context(errors, file_metadata, tier1_result)

        result = ai_service.analyze_errors(
          errors: errors,
          file_metadata: enhanced_context,
          tier: "tier2",
          user: @user
        )

        if result.success?
          # Deduct Tier 2 tokens
          @user.consume_tokens!(calculate_tier2_cost(result.value[:credits_used]))

          # Merge insights from both tiers
          merged_result = merge_tier_results(tier1_result, result.value)
          merged_result[:tier_used] = "tier2"
          merged_result[:escalation_reason] = determine_escalation_reason(tier1_result)

          Rails.logger.info("Tier 2 analysis completed. Total tokens used: #{merged_result[:total_credits_used]}")

          Common::Result.success(merged_result)
        else
          # Fallback to Tier 1 if Tier 2 fails
          Rails.logger.warn("Tier 2 analysis failed, falling back to Tier 1 result")
          tier1_result[:tier_used] = "tier1"
          tier1_result[:escalation_reason] = "Tier 2 failed - using Tier 1 result"
          Common::Result.success(tier1_result)
        end
      end

      def should_escalate_to_tier2?(tier1_result, errors)
        # Check confidence threshold
        confidence = tier1_result[:overall_confidence] || 0.0
        return true if confidence < CONFIDENCE_THRESHOLD

        # Check error complexity
        return true if has_complex_errors?(errors)

        # Check user tier eligibility
        return true if @user.pro? && has_high_severity_errors?(errors)

        # Check file complexity
        return true if is_complex_file?(tier1_result)

        false
      end

      def has_complex_errors?(errors)
        complex_types = [ "circular_reference", "complex_formula_error", "data_integrity_issue" ]
        errors.any? { |error| complex_types.include?(error[:type]) }
      end

      def has_high_severity_errors?(errors)
        errors.any? { |error| error[:severity] == "high" }
      end

      def is_complex_file?(tier1_result)
        # Consider file complex if it has many errors or specific patterns
        error_count = tier1_result[:analysis]&.keys&.size || 0
        error_count > 10
      end

      def build_tier2_context(errors, file_metadata, tier1_result)
        file_metadata.merge(
          tier1_analysis: tier1_result[:analysis],
          tier1_confidence: tier1_result[:overall_confidence],
          error_patterns: analyze_error_patterns(errors),
          complexity_score: calculate_complexity_score(errors)
        )
      end

      def analyze_error_patterns(errors)
        patterns = {
          formula_errors: errors.count { |e| e[:type] == "formula_error" },
          data_errors: errors.count { |e| e[:type] == "data_validation" },
          circular_refs: errors.count { |e| e[:type] == "circular_reference" }
        }

        patterns[:dominant_pattern] = patterns.max_by { |_, count| count }.first
        patterns
      end

      def calculate_complexity_score(errors)
        # Weight by severity
        severity_weights = { "high" => 3, "medium" => 2, "low" => 1 }
        weighted_score = errors.sum { |error| severity_weights[error[:severity]] || 1 }

        # Normalize to 0-1 scale
        [ weighted_score / 100.0, 1.0 ].min
      end

      def merge_tier_results(tier1_result, tier2_result)
        {
          analysis: tier2_result[:analysis],
          corrections: tier2_result[:corrections],
          overall_confidence: tier2_result[:overall_confidence],
          summary: tier2_result[:summary],
          estimated_time_saved: tier2_result[:estimated_time_saved],

          # Tier-specific info
          tier1_confidence: tier1_result[:overall_confidence],
          tier2_confidence: tier2_result[:overall_confidence],
          confidence_improvement: tier2_result[:overall_confidence] - tier1_result[:overall_confidence],

          # Token usage
          tier1_credits_used: tier1_result[:credits_used],
          tier2_credits_used: tier2_result[:credits_used],
          total_credits_used: tier1_result[:credits_used] + tier2_result[:credits_used],

          # Provider info
          tier1_provider: tier1_result[:provider_used],
          tier2_provider: tier2_result[:provider_used]
        }
      end

      def determine_escalation_reason(tier1_result)
        confidence = tier1_result[:overall_confidence] || 0.0

        if confidence < CONFIDENCE_THRESHOLD
          "Low confidence (#{confidence.round(2)}) - below threshold (#{CONFIDENCE_THRESHOLD})"
        else
          "Complex error patterns detected requiring advanced analysis"
        end
      end

      def validate_tier1_access
        return if !Rails.application.config.features[:subscription_required]

        unless @user.credits >= calculate_tier1_cost(500) # Estimated cost
          raise Common::Errors::InsufficientCreditsError.new(
            message: "Insufficient credits for Tier 1 AI analysis",
            required_credits: calculate_tier1_cost(500),
            current_credits: @user.credits
          )
        end
      end

      def validate_tier2_access
        return if !Rails.application.config.features[:subscription_required]

        required_credits = calculate_tier2_cost(1000) # Estimated cost

        unless @user.credits >= required_credits
          raise Common::Errors::InsufficientCreditsError.new(
            message: "Insufficient credits for Tier 2 AI analysis",
            required_credits: required_credits,
            current_credits: @user.credits
          )
        end

        unless @user.pro? || @user.enterprise?
          raise Common::Errors::AuthorizationError.new(
            message: "Tier 2 AI analysis requires PRO or ENTERPRISE subscription"
          )
        end
      end

      def calculate_tier1_cost(credits_used)
        # Tier 1: 1 token per 100 AI tokens
        (credits_used / 100.0).ceil
      end

      def calculate_tier2_cost(credits_used)
        # Tier 2: 1 token per 20 AI tokens (5x more expensive)
        (credits_used / 20.0).ceil
      end
    end
  end
end
