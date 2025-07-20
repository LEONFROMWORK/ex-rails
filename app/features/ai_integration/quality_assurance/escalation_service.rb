# frozen_string_literal: true

module AiIntegration
  module QualityAssurance
    class EscalationService
      # Quality thresholds for escalation
      TIER1_QUALITY_THRESHOLD = 7.5
      TIER2_QUALITY_THRESHOLD = 8.5

      # Escalation reasons
      ESCALATION_REASONS = {
        low_quality: "Quality score below threshold",
        complexity_mismatch: "Question complexity requires higher tier",
        user_preference: "User subscription allows higher tier",
        previous_failure: "Previous tier failed to provide response",
        confidence_low: "Low confidence in response accuracy"
      }.freeze

      def initialize
        @llm_judge = LlmJudgeService.new
        @escalation_history = {}
      end

      def should_escalate?(current_tier:, response:, question:, context: {})
        escalation_decision = {
          should_escalate: false,
          recommended_tier: current_tier,
          reasons: [],
          confidence: 0.0
        }

        # Quality-based escalation
        if response.present?
          quality_assessment = @llm_judge.assess_response_quality(
            original_question: question,
            ai_response: response,
            context: context
          )

          escalation_decision[:quality_score] = quality_assessment[:overall_score]
          escalation_decision[:quality_assessment] = quality_assessment

          # Check quality thresholds
          if current_tier == "tier1" && quality_assessment[:overall_score] < TIER1_QUALITY_THRESHOLD
            escalation_decision[:should_escalate] = true
            escalation_decision[:recommended_tier] = "tier2"
            escalation_decision[:reasons] << ESCALATION_REASONS[:low_quality]
          elsif current_tier == "tier2" && quality_assessment[:overall_score] < TIER2_QUALITY_THRESHOLD
            escalation_decision[:should_escalate] = true
            escalation_decision[:recommended_tier] = "tier3"
            escalation_decision[:reasons] << ESCALATION_REASONS[:low_quality]
          end

          escalation_decision[:confidence] = quality_assessment[:confidence]
        end

        # Complexity-based escalation
        complexity_analysis = analyze_question_complexity(question)
        if complexity_analysis[:requires_escalation]
          escalation_decision[:should_escalate] = true
          escalation_decision[:recommended_tier] = complexity_analysis[:recommended_tier]
          escalation_decision[:reasons] << ESCALATION_REASONS[:complexity_mismatch]
        end

        # Historical escalation patterns
        if should_escalate_based_on_history?(question, current_tier)
          escalation_decision[:should_escalate] = true
          escalation_decision[:recommended_tier] = get_historical_successful_tier(question)
          escalation_decision[:reasons] << "Historical pattern suggests higher tier needed"
        end

        escalation_decision[:timestamp] = Time.current.iso8601
        escalation_decision
      end

      def record_escalation_result(original_tier:, escalated_tier:, question:, success:, quality_score: nil)
        escalation_key = generate_escalation_key(question)

        @escalation_history[escalation_key] ||= []
        @escalation_history[escalation_key] << {
          original_tier: original_tier,
          escalated_tier: escalated_tier,
          success: success,
          quality_score: quality_score,
          timestamp: Time.current.iso8601
        }

        # Keep only last 10 escalations per pattern
        if @escalation_history[escalation_key].size > 10
          @escalation_history[escalation_key].shift
        end

        Rails.logger.info("Recorded escalation result: #{original_tier} -> #{escalated_tier}, Success: #{success}")
      end

      def get_escalation_statistics
        total_escalations = @escalation_history.values.flatten.size
        successful_escalations = @escalation_history.values.flatten.count { |e| e[:success] }

        {
          total_escalations: total_escalations,
          successful_escalations: successful_escalations,
          success_rate: total_escalations > 0 ? successful_escalations.to_f / total_escalations : 0.0,
          escalation_patterns: @escalation_history.size,
          tier_distribution: calculate_tier_distribution,
          average_quality_improvement: calculate_average_quality_improvement
        }
      end

      def optimize_escalation_thresholds
        # Analyze historical data to optimize thresholds
        escalation_data = @escalation_history.values.flatten

        tier1_escalations = escalation_data.select { |e| e[:original_tier] == "tier1" }
        tier2_escalations = escalation_data.select { |e| e[:original_tier] == "tier2" }

        recommendations = {
          current_thresholds: {
            tier1: TIER1_QUALITY_THRESHOLD,
            tier2: TIER2_QUALITY_THRESHOLD
          },
          recommended_thresholds: {},
          analysis: {}
        }

        if tier1_escalations.any?
          successful_tier1 = tier1_escalations.select { |e| e[:success] }
          avg_quality_before = successful_tier1.map { |e| e[:quality_score] }.compact.sum / successful_tier1.size

          recommendations[:recommended_thresholds][:tier1] = [ avg_quality_before - 0.5, 6.0 ].max
          recommendations[:analysis][:tier1] = "Based on #{tier1_escalations.size} escalations"
        end

        if tier2_escalations.any?
          successful_tier2 = tier2_escalations.select { |e| e[:success] }
          avg_quality_before = successful_tier2.map { |e| e[:quality_score] }.compact.sum / successful_tier2.size

          recommendations[:recommended_thresholds][:tier2] = [ avg_quality_before - 0.5, 7.0 ].max
          recommendations[:analysis][:tier2] = "Based on #{tier2_escalations.size} escalations"
        end

        recommendations
      end

      private

      def analyze_question_complexity(question)
        complexity_score = 0

        # Length factor
        complexity_score += 1 if question.length > 200
        complexity_score += 1 if question.length > 500

        # Complex Excel functions
        complex_functions = %w[vlookup hlookup index match sumifs countifs xlookup pivot macro vba array]
        complex_functions.each do |func|
          complexity_score += 1 if question.downcase.include?(func)
        end

        # Multiple conditions/criteria
        complexity_score += 1 if question.downcase.match?(/multiple|several|various/)
        complexity_score += 1 if question.downcase.match?(/and|or/) && question.count("|") > 1

        # Advanced topics
        advanced_topics = %w[automation dashboard visualization power query power pivot]
        advanced_topics.each do |topic|
          complexity_score += 2 if question.downcase.include?(topic)
        end

        # Determine escalation need
        analysis = {
          complexity_score: complexity_score,
          requires_escalation: false,
          recommended_tier: "tier1"
        }

        case complexity_score
        when 4..6
          analysis[:requires_escalation] = true
          analysis[:recommended_tier] = "tier2"
        when 7..Float::INFINITY
          analysis[:requires_escalation] = true
          analysis[:recommended_tier] = "tier3"
        end

        analysis
      end

      def should_escalate_based_on_history?(question, current_tier)
        escalation_key = generate_escalation_key(question)
        history = @escalation_history[escalation_key]

        return false unless history&.any?

        # Check if similar questions consistently needed higher tiers
        recent_escalations = history.last(5)
        successful_escalations = recent_escalations.select { |e| e[:success] }

        if successful_escalations.size >= 2
          most_common_successful_tier = successful_escalations
                                       .group_by { |e| e[:escalated_tier] }
                                       .max_by { |_, escalations| escalations.size }
                                       &.first

          return tier_is_higher?(most_common_successful_tier, current_tier)
        end

        false
      end

      def get_historical_successful_tier(question)
        escalation_key = generate_escalation_key(question)
        history = @escalation_history[escalation_key]

        return "tier2" unless history&.any?

        successful_escalations = history.select { |e| e[:success] }
        return "tier2" unless successful_escalations.any?

        # Return the most commonly successful tier
        successful_escalations
          .group_by { |e| e[:escalated_tier] }
          .max_by { |_, escalations| escalations.size }
          &.first || "tier2"
      end

      def generate_escalation_key(question)
        # Create a key based on question characteristics
        key_parts = []

        # Add length category
        case question.length
        when 0..100 then key_parts << "short"
        when 101..300 then key_parts << "medium"
        else key_parts << "long"
        end

        # Add function types
        excel_functions = %w[sum average count vlookup hlookup index match sumifs countifs]
        found_functions = excel_functions.select { |func| question.downcase.include?(func) }
        key_parts << found_functions.first(2).join("_") if found_functions.any?

        # Add complexity indicators
        if question.downcase.include?("complex") || question.downcase.include?("advanced")
          key_parts << "complex"
        end

        key_parts.join("_")
      end

      def tier_is_higher?(tier1, tier2)
        tier_order = { "tier1" => 1, "tier2" => 2, "tier3" => 3 }
        tier_order[tier1] > tier_order[tier2]
      end

      def calculate_tier_distribution
        all_escalations = @escalation_history.values.flatten

        distribution = { "tier1" => 0, "tier2" => 0, "tier3" => 0 }

        all_escalations.each do |escalation|
          distribution[escalation[:escalated_tier]] += 1
        end

        distribution
      end

      def calculate_average_quality_improvement
        escalations_with_quality = @escalation_history.values.flatten.select { |e| e[:quality_score] }

        return 0.0 if escalations_with_quality.empty?

        # This is a simplified calculation - in reality, you'd compare before/after quality scores
        escalations_with_quality.map { |e| e[:quality_score] }.sum / escalations_with_quality.size
      end
    end
  end
end
