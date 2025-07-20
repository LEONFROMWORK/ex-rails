# frozen_string_literal: true

module AiIntegration
  module QualityAssurance
    class LlmJudgeService
      JUDGE_MODEL_TIER = "tier3" # Use highest tier for quality assessment
      QUALITY_DIMENSIONS = %w[accuracy completeness clarity relevance practicality].freeze

      def initialize
        @provider_manager = MultiProvider::ProviderManager.new(primary_provider: "openrouter")
      end

      def assess_response_quality(original_question:, ai_response:, context: {})
        Rails.logger.info("LLM Judge: Assessing response quality")

        # Build assessment prompt
        assessment_prompt = build_assessment_prompt(original_question, ai_response, context)

        # Get judge response
        judge_response = @provider_manager.generate_response(
          prompt: assessment_prompt,
          max_tokens: 1000,
          temperature: 0.1, # Low temperature for consistent judgment
          tier: JUDGE_MODEL_TIER
        )

        if judge_response.success?
          parse_quality_assessment(judge_response.value)
        else
          Rails.logger.error("LLM Judge failed: #{judge_response.error}")
          fallback_quality_assessment(ai_response)
        end
      end

      def batch_assess_responses(responses)
        results = []

        responses.each_slice(5) do |batch|
          batch_results = batch.map do |response_data|
            assess_response_quality(
              original_question: response_data[:question],
              ai_response: response_data[:response],
              context: response_data[:context] || {}
            )
          end

          results.concat(batch_results)

          # Rate limiting
          sleep(0.2) if batch.size > 3
        end

        results
      end

      def get_quality_statistics(responses)
        return {} if responses.empty?

        assessments = responses.map { |r| assess_response_quality(**r) }

        {
          total_responses: assessments.size,
          average_overall_score: assessments.map { |a| a[:overall_score] }.sum / assessments.size,
          dimension_averages: calculate_dimension_averages(assessments),
          quality_distribution: calculate_quality_distribution(assessments),
          recommendation_summary: generate_recommendation_summary(assessments)
        }
      end

      private

      def build_assessment_prompt(question, ai_response, context)
        <<~PROMPT
          You are an expert evaluator of AI responses for Excel-related questions. Please assess the following AI response across multiple quality dimensions.

          **Original Question:**
          #{question}

          **Context:**
          #{context.to_json if context.any?}

          **AI Response to Evaluate:**
          #{ai_response}

          **Assessment Instructions:**
          Rate the response on a scale of 1-10 for each dimension:

          1. **Accuracy** (1-10): How technically correct is the information?
          2. **Completeness** (1-10): Does it fully address the question?
          3. **Clarity** (1-10): How clear and understandable is the explanation?
          4. **Relevance** (1-10): How relevant is the response to the specific question?
          5. **Practicality** (1-10): How actionable and useful is the response?

          **Required Output Format (JSON only):**
          {
            "accuracy": 8,
            "completeness": 7,
            "clarity": 9,
            "relevance": 8,
            "practicality": 7,
            "overall_score": 7.8,
            "strengths": ["Clear step-by-step instructions", "Correct formula syntax"],
            "weaknesses": ["Could include more examples", "Missing edge case handling"],
            "improvement_suggestions": ["Add more detailed examples", "Include troubleshooting tips"],
            "confidence": 0.85
          }

          Provide only the JSON response without any additional text.
        PROMPT
      end

      def parse_quality_assessment(response)
        content = response[:content]

        # Extract JSON from response
        json_content = extract_json_from_response(content)

        begin
          parsed = JSON.parse(json_content)

          # Validate and normalize the response
          assessment = {
            accuracy: normalize_score(parsed["accuracy"]),
            completeness: normalize_score(parsed["completeness"]),
            clarity: normalize_score(parsed["clarity"]),
            relevance: normalize_score(parsed["relevance"]),
            practicality: normalize_score(parsed["practicality"]),
            overall_score: normalize_score(parsed["overall_score"]),
            strengths: parsed["strengths"] || [],
            weaknesses: parsed["weaknesses"] || [],
            improvement_suggestions: parsed["improvement_suggestions"] || [],
            confidence: [ parsed["confidence"]&.to_f || 0.5, 1.0 ].min,
            judge_model: response[:model] || "unknown",
            assessment_timestamp: Time.current.iso8601
          }

          # Calculate overall score if not provided
          if assessment[:overall_score] == 0
            dimension_scores = [
              assessment[:accuracy],
              assessment[:completeness],
              assessment[:clarity],
              assessment[:relevance],
              assessment[:practicality]
            ]
            assessment[:overall_score] = dimension_scores.sum / dimension_scores.size
          end

          Rails.logger.info("LLM Judge: Quality assessed with overall score #{assessment[:overall_score]}")
          assessment

        rescue JSON::ParserError => e
          Rails.logger.error("LLM Judge: Failed to parse assessment - #{e.message}")
          fallback_quality_assessment(response[:content])
        end
      end

      def extract_json_from_response(content)
        # Remove markdown code blocks
        content = content.gsub(/```json\n?/, "").gsub(/```\n?/, "")

        # Find JSON object
        json_start = content.index("{")
        json_end = content.rindex("}")

        if json_start && json_end && json_end > json_start
          content[json_start..json_end]
        else
          content
        end
      end

      def normalize_score(score)
        return 0 unless score

        numeric_score = score.to_f
        [ [ numeric_score, 0 ].max, 10 ].min
      end

      def fallback_quality_assessment(response_content)
        # Simple heuristic-based quality assessment
        Rails.logger.info("LLM Judge: Using fallback quality assessment")

        content_length = response_content.length
        has_formulas = response_content.match?(/=\w+\(/)
        has_steps = response_content.match?(/\d+\.\s/)
        has_examples = response_content.match?(/example|for instance/i)

        # Basic scoring
        base_score = 5.0
        base_score += 1.0 if content_length > 200
        base_score += 1.0 if has_formulas
        base_score += 1.0 if has_steps
        base_score += 1.0 if has_examples

        overall_score = [ base_score, 10.0 ].min

        {
          accuracy: overall_score,
          completeness: overall_score,
          clarity: overall_score,
          relevance: overall_score,
          practicality: overall_score,
          overall_score: overall_score,
          strengths: [ "Response provided" ],
          weaknesses: [ "Quality assessment unavailable" ],
          improvement_suggestions: [ "Use LLM judge for detailed assessment" ],
          confidence: 0.3,
          judge_model: "fallback_heuristic",
          assessment_timestamp: Time.current.iso8601
        }
      end

      def calculate_dimension_averages(assessments)
        return {} if assessments.empty?

        QUALITY_DIMENSIONS.each_with_object({}) do |dimension, averages|
          scores = assessments.map { |a| a[dimension.to_sym] }.compact
          averages[dimension] = scores.any? ? scores.sum / scores.size : 0
        end
      end

      def calculate_quality_distribution(assessments)
        return {} if assessments.empty?

        overall_scores = assessments.map { |a| a[:overall_score] }.compact

        {
          excellent: overall_scores.count { |s| s >= 8.5 },
          good: overall_scores.count { |s| s >= 7.0 && s < 8.5 },
          fair: overall_scores.count { |s| s >= 5.5 && s < 7.0 },
          poor: overall_scores.count { |s| s < 5.5 }
        }
      end

      def generate_recommendation_summary(assessments)
        return {} if assessments.empty?

        # Aggregate common weaknesses and suggestions
        all_weaknesses = assessments.flat_map { |a| a[:weaknesses] }.compact
        all_suggestions = assessments.flat_map { |a| a[:improvement_suggestions] }.compact

        common_weaknesses = all_weaknesses.tally.sort_by { |_, count| -count }.first(3)
        common_suggestions = all_suggestions.tally.sort_by { |_, count| -count }.first(3)

        {
          common_weaknesses: common_weaknesses.map(&:first),
          common_suggestions: common_suggestions.map(&:first),
          overall_health: calculate_overall_health(assessments)
        }
      end

      def calculate_overall_health(assessments)
        average_score = assessments.map { |a| a[:overall_score] }.sum / assessments.size

        case average_score
        when 8.5..10.0 then "excellent"
        when 7.0...8.5 then "good"
        when 5.5...7.0 then "fair"
        else "needs_improvement"
        end
      end
    end
  end
end
