# frozen_string_literal: true

module AiIntegration
  module MultiProvider
    class AiAnalysisService
      attr_reader :provider_manager

      def initialize(primary_provider: "openrouter")
        @provider_manager = ProviderManager.new(primary_provider: primary_provider)
        @rag_orchestrator = RagSystem::RagOrchestrator.new
        @llm_judge = QualityAssurance::LlmJudgeService.new
        @escalation_service = QualityAssurance::EscalationService.new
      end

      def analyze_errors(errors:, file_metadata:, tier: "tier1", user: nil, images: nil)
        validate_tier_access(tier, user) if user

        # Build RAG-enhanced prompt
        rag_prompt_data = build_rag_enhanced_prompt(errors, file_metadata, tier, images)

        # Set max_tokens based on tier
        max_tokens = case tier
        when "tier3" then 3000
        when "tier2" then 2000
        else 1000
        end

        response = @provider_manager.generate_response(
          prompt: rag_prompt_data[:user_prompt],
          max_tokens: max_tokens,
          temperature: 0.3,
          tier: tier,
          images: images
        )

        if response.success?
          result = parse_ai_response(response.value)
          if result.success?
            # Add provider info to result
            result.value[:provider_used] = @provider_manager.current_provider
            result.value[:tier_requested] = tier
            result.value[:rag_enhanced] = true
            result.value[:rag_documents_used] = rag_prompt_data[:rag_data][:documents_found]
          end
          result
        else
          response
        end
      rescue StandardError => e
        Rails.logger.error("AI analysis failed: #{e.message}")
        Common::Result.failure(
          Common::Errors::AIProviderError.new(
            provider: @provider_manager.current_provider,
            message: e.message
          )
        )
      end

      # New method for 3-tier intelligent analysis
      def analyze_with_intelligent_tier_system(errors:, file_metadata:, user:, images: nil)
        tier_manager = ThreeTierManager.new(user: user)
        tier_manager.analyze_excel_with_intelligence(
          errors: errors,
          file_metadata: file_metadata,
          images: images
        )
      end

      # Legacy method for 2-tier analysis (backward compatibility)
      def analyze_with_tier_system(errors:, file_metadata:, user:)
        tier_manager = TierManager.new(user: user)
        tier_manager.analyze_excel(nil, errors: errors, file_metadata: file_metadata)
      end

      def provider_status
        @provider_manager.provider_status
      end

      def index_excel_knowledge(content, metadata = {})
        @rag_orchestrator.index_excel_knowledge(content, metadata)
      end

      def get_rag_statistics
        @rag_orchestrator.get_rag_statistics
      end

      # Quality-assured analysis with automatic escalation
      def analyze_errors_with_quality_assurance(errors:, file_metadata:, tier: "tier1", user: nil, images: nil)
        Rails.logger.info("Starting quality-assured analysis with tier: #{tier}")

        # Initial analysis
        result = analyze_errors(
          errors: errors,
          file_metadata: file_metadata,
          tier: tier,
          user: user,
          images: images
        )

        return result if result.failure?

        # Build question for escalation analysis
        question = build_question_from_errors(errors)

        # Check if escalation is needed
        escalation_decision = @escalation_service.should_escalate?(
          current_tier: tier,
          response: result.value[:summary],
          question: question,
          context: { file_metadata: file_metadata }
        )

        # If escalation is recommended and possible
        if escalation_decision[:should_escalate] && can_escalate_tier?(escalation_decision[:recommended_tier], user)
          Rails.logger.info("Escalating from #{tier} to #{escalation_decision[:recommended_tier]}")

          escalated_result = analyze_errors(
            errors: errors,
            file_metadata: file_metadata,
            tier: escalation_decision[:recommended_tier],
            user: user,
            images: images
          )

          if escalated_result.success?
            # Record successful escalation
            @escalation_service.record_escalation_result(
              original_tier: tier,
              escalated_tier: escalation_decision[:recommended_tier],
              question: question,
              success: true,
              quality_score: escalation_decision[:quality_score]
            )

            # Merge results
            merged_result = merge_escalated_results(result.value, escalated_result.value, tier, escalation_decision)
            return Common::Result.success(merged_result)
          else
            # Record failed escalation
            @escalation_service.record_escalation_result(
              original_tier: tier,
              escalated_tier: escalation_decision[:recommended_tier],
              question: question,
              success: false
            )
          end
        end

        # Add quality assessment to original result
        result.value[:quality_assessment] = escalation_decision[:quality_assessment] if escalation_decision[:quality_assessment]
        result.value[:escalation_considered] = true
        result.value[:escalation_reasons] = escalation_decision[:reasons] if escalation_decision[:reasons]

        result
      end

      def get_quality_statistics
        {
          llm_judge: @llm_judge,
          escalation_service: @escalation_service.get_escalation_statistics
        }
      end

      private

      def build_rag_enhanced_prompt(errors, file_metadata, tier, images)
        # Build query for RAG search
        error_descriptions = errors.map { |e| e[:description] || e[:message] }.join(" ")
        query = "Excel errors: #{error_descriptions}"

        # Add file context
        context = build_file_context(file_metadata)

        # Get RAG enhancement
        @rag_orchestrator.build_rag_prompt(query, context: context, images: images, tier: tier)
      end

      def build_file_context(file_metadata)
        context_parts = []

        context_parts << "File: #{file_metadata[:filename]}" if file_metadata[:filename]
        context_parts << "Sheets: #{file_metadata[:sheet_count]}" if file_metadata[:sheet_count]
        context_parts << "Formulas: #{file_metadata[:formula_count]}" if file_metadata[:formula_count]
        context_parts << "Size: #{file_metadata[:file_size]} bytes" if file_metadata[:file_size]

        context_parts.join(", ")
      end

      def build_question_from_errors(errors)
        error_descriptions = errors.map { |e| e[:description] || e[:message] || e[:type] }.compact
        "Excel errors: #{error_descriptions.join(', ')}"
      end

      def can_escalate_tier?(recommended_tier, user)
        return false unless user

        case recommended_tier
        when "tier3"
          user.enterprise? && user.credits >= 100
        when "tier2"
          (user.pro? || user.enterprise?) && user.credits >= 50
        else
          true
        end
      end

      def merge_escalated_results(original_result, escalated_result, original_tier, escalation_decision)
        {
          # Use escalated result as primary
          analysis: escalated_result[:analysis],
          corrections: escalated_result[:corrections],
          overall_confidence: escalated_result[:overall_confidence],
          summary: escalated_result[:summary],
          estimated_time_saved: escalated_result[:estimated_time_saved],

          # Escalation metadata
          escalated_from: original_tier,
          escalated_to: escalation_decision[:recommended_tier],
          escalation_reasons: escalation_decision[:reasons],

          # Quality comparison
          original_quality: escalation_decision[:quality_score],
          escalated_quality: escalation_decision[:quality_assessment]&.dig(:overall_score),

          # Combined metadata
          **escalated_result.except(:analysis, :corrections, :overall_confidence, :summary, :estimated_time_saved),
          escalation_performed: true,
          escalation_timestamp: Time.current.iso8601
        }
      end

      def validate_tier_access(tier, user)
        case tier
        when "tier3"
          unless user.credits >= 100 && user.enterprise?
            raise Common::Errors::InsufficientCreditsError.new(
              message: "Tier 3 AI analysis requires ENTERPRISE subscription and 100+ credits",
              required_credits: 100,
              current_credits: user.credits
            )
          end
        when "tier2"
          unless user.credits >= 50 && (user.pro? || user.enterprise?)
            raise Common::Errors::InsufficientCreditsError.new(
              message: "Tier 2 AI analysis requires PRO subscription and 50+ credits",
              required_credits: 50,
              current_credits: user.credits
            )
          end
        when "tier1"
          unless user.credits >= 5
            raise Common::Errors::InsufficientCreditsError.new(
              message: "AI analysis requires at least 5 credits",
              required_credits: 5,
              current_credits: user.credits
            )
          end
        end
      end

      def build_analysis_prompt(errors, file_metadata, tier)
        system_prompt = case tier
        when "tier3"
                          "You are a world-class Excel expert with deep expertise in advanced analytics, VBA, Power Query, and enterprise-level Excel optimization."
        when "tier2"
                          "You are a senior Excel expert with advanced analytical capabilities."
        else
                          "You are an Excel expert analyzing errors in a spreadsheet."
        end

        analysis_depth = case tier
        when "tier3"
                           <<~DEPTH
                             Provide:
                             1. Comprehensive technical analysis with Excel internals and architecture insights
                             2. Advanced root cause analysis with dependency mapping and data flow analysis
                             3. Performance impact assessment with optimization recommendations
                             4. Multiple correction options with detailed trade-offs and implementation complexity
                             5. Preventive recommendations with best practices and governance strategies
                             6. Code quality improvements for complex formulas with refactoring suggestions
                             7. Enterprise-level recommendations for scalability and maintainability
                             8. Advanced features utilization (Power Query, Power Pivot, VBA alternatives)
                           DEPTH
        when "tier2"
                           <<~DEPTH
                             Provide:
                             1. Deep technical analysis of each error including Excel internals
                             2. Root cause analysis with dependency mapping
                             3. Performance impact assessment
                             4. Multiple correction options with trade-offs
                             5. Preventive recommendations for similar issues
                             6. Code quality improvements for complex formulas
                           DEPTH
        else
                           <<~DEPTH
                             Provide:
                             1. Clear analysis of each error
                             2. Direct corrections that should be applied
                             3. Basic explanation of the fixes
                           DEPTH
        end

        <<~PROMPT
          #{system_prompt}

          File metadata:
          ```json
          #{file_metadata.to_json}
          ```

          Detected errors:
          ```json
          #{errors.to_json}
          ```

          #{analysis_depth}

          Respond in valid JSON format only:
          {
            "analysis": {
              "error_1": {#{' '}
                "explanation": "Clear explanation of the error",
                "impact": "High/Medium/Low - business impact",
                "root_cause": "Technical root cause",
                "severity": "Critical/High/Medium/Low"
              }
            },
            "corrections": [
              {
                "cell": "A1",
                "original": "=SUM(A:A)",
                "corrected": "=SUM(A2:A100)",
                "explanation": "Why this correction fixes the issue",
                "confidence": 0.95
              }
            ],
            "overall_confidence": 0.85,
            "summary": "Brief summary of all issues and recommended actions",
            "estimated_time_saved": "X hours/minutes of manual correction"
          }
        PROMPT
      end

      def parse_ai_response(response)
        content = response[:content]

        # Clean up response content if needed
        content = extract_json_from_response(content)

        parsed = JSON.parse(content)

        # Validate required fields
        validate_ai_response_structure(parsed)

        Common::Result.success({
          analysis: parsed["analysis"] || {},
          corrections: parsed["corrections"] || [],
          overall_confidence: parsed["overall_confidence"]&.to_f || 0.0,
          summary: parsed["summary"] || "No summary provided",
          estimated_time_saved: parsed["estimated_time_saved"] || "Unknown",
          credits_used: response[:usage][:total_tokens],
          raw_response: response
        })
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse AI response: #{e.message}")
        Rails.logger.error("Raw response: #{response[:content]}")
        Common::Result.failure("Invalid AI response format: #{e.message}")
      rescue => e
        Rails.logger.error("Error processing AI response: #{e.message}")
        Common::Result.failure("Error processing AI response: #{e.message}")
      end

      def extract_json_from_response(content)
        # Remove markdown code blocks if present
        content = content.gsub(/```json\n?/, "").gsub(/```\n?/, "")

        # Find JSON object start and end
        json_start = content.index("{")
        json_end = content.rindex("}")

        if json_start && json_end && json_end > json_start
          content[json_start..json_end]
        else
          content
        end
      end

      def validate_ai_response_structure(parsed)
        unless parsed.is_a?(Hash)
          raise StandardError, "Response must be a JSON object"
        end

        unless parsed.key?("analysis") || parsed.key?("corrections")
          raise StandardError, "Response must contain 'analysis' or 'corrections'"
        end
      end
    end
  end
end
