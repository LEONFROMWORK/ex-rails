# frozen_string_literal: true

module AiIntegration
  module Jobs
    class AnalyzeErrorsJob < ApplicationJob
      queue_as :ai_analysis

      def perform(analysis_id:, user_tier:)
        analysis = Analysis.find(analysis_id)

        # Determine AI tier based on user tier and confidence requirements
        ai_tier = determine_ai_tier(user_tier, analysis.detected_errors)

        # Perform AI analysis
        ai_service = AiIntegration::MultiProvider::AiAnalysisService.new(
          provider: determine_provider(ai_tier)
        )

        result = ai_service.analyze_errors(
          errors: analysis.detected_errors,
          file_metadata: analysis.excel_file.metadata,
          tier: ai_tier
        )

        if result.success?
          ai_response = result.value

          analysis.update!(
            ai_analysis: ai_response[:analysis],
            corrections: ai_response[:corrections],
            ai_tier_used: ai_tier,
            confidence_score: ai_response[:confidence],
            credits_used: ai_response[:credits_used],
            cost: calculate_cost(ai_response[:credits_used], ai_tier),
            fixed_count: ai_response[:corrections]&.count || 0,
            analysis_summary: ai_response[:summary],
            status: "completed"
          )

          # Update Excel file status
          analysis.excel_file.update!(status: "completed")

          # Deduct tokens from user
          analysis.user.consume_tokens!(ai_response[:credits_used])

          # Broadcast completion
          broadcast_completion(analysis)
        else
          handle_ai_failure(analysis, result.error)
        end
      rescue StandardError => e
        handle_ai_failure(analysis, e.message)
        raise
      end

      private

      def determine_ai_tier(user_tier, errors)
        # Complex errors or low confidence trigger tier 2
        complexity = calculate_complexity(errors)

        case user_tier
        when "free", "basic"
          complexity > 0.7 ? "tier1" : "tier1"
        when "pro", "enterprise"
          complexity > 0.5 ? "tier2" : "tier1"
        else
          "tier1"
        end
      end

      def determine_provider(ai_tier)
        # Could implement load balancing or cost optimization here
        case ai_tier
        when "tier1"
          [ "openai", "anthropic" ].sample
        when "tier2"
          "anthropic" # Prefer Claude for complex analysis
        else
          "openai"
        end
      end

      def calculate_complexity(errors)
        return 0.0 if errors.empty?

        high_severity_count = errors.count { |e| e[:severity] == "high" }
        total_count = errors.count

        (high_severity_count.to_f / total_count).round(2)
      end

      def calculate_cost(credits_used, ai_tier)
        # Cost per 1000 tokens (approximate)
        cost_per_1k = case ai_tier
        when "tier1" then 0.001 # $0.001 per 1K tokens
        when "tier2" then 0.03  # $0.03 per 1K tokens
        else 0.001
        end

        (credits_used / 1000.0 * cost_per_1k).round(6)
      end

      def handle_ai_failure(analysis, error_message)
        analysis.update!(
          status: "failed",
          analysis_summary: "AI analysis failed: #{error_message}"
        )

        analysis.excel_file.update!(status: "failed")

        broadcast_error(analysis, error_message)
      end

      def broadcast_completion(analysis)
        ActionCable.server.broadcast(
          "excel_analysis_#{analysis.excel_file_id}",
          {
            type: "completed",
            analysis_id: analysis.id,
            summary: analysis.analysis_summary,
            errors_found: analysis.error_count,
            errors_fixed: analysis.fixed_count,
            confidence: analysis.confidence_score
          }
        )
      end

      def broadcast_error(analysis, error_message)
        ActionCable.server.broadcast(
          "excel_analysis_#{analysis.excel_file_id}",
          {
            type: "error",
            message: "AI analysis failed: #{error_message}"
          }
        )
      end
    end
  end
end
