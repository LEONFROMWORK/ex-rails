# frozen_string_literal: true

module AiIntegration
  module Commands
    # Command for image analysis
    # Follows Single Responsibility Principle (SRP)
    class AnalyzeImage < Shared::Contracts::Command
      include ActiveModel::Attributes

      attribute :image_data
      attribute :prompt, :string
      attribute :user_id, :integer
      attribute :analysis_type, :string, default: "general"
      attribute :tier, :string, default: "cost_effective"
      attribute :options, default: {}

      validates :image_data, :prompt, :user_id, presence: true
      validates :analysis_type, inclusion: { in: %w[general chart_analysis formula_analysis data_validation conversation template] }
      validates :tier, inclusion: { in: %w[cost_effective balanced premium] }

      def initialize(dependencies = {})
        super()
        @provider_factory = dependencies[:provider_factory] || AiIntegration::Factories::ProviderFactory.new
        @usage_tracker = dependencies[:usage_tracker] || AiIntegration::Services::UsageTracker.new
      end

      private

      def execute
        # Create appropriate provider based on tier
        provider = @provider_factory.create_multimodal_provider(tier.to_sym)

        # Build analysis context
        context = build_analysis_context

        # Perform image analysis
        analysis_result = provider.analyze_image(
          image_data: image_data,
          prompt: enhanced_prompt,
          context: context,
          options: options
        )

        return analysis_result if analysis_result.failure?

        # Track usage
        track_usage(analysis_result.value)

        # Return enhanced result
        Shared::Types::Result.success(
          value: enhance_analysis_result(analysis_result.value)
        )
      rescue => error
        Shared::Types::Result.failure(error: "Image analysis failed: #{error.message}")
      end

      def build_analysis_context
        context = {
          analysis_type: analysis_type,
          user_tier: determine_user_tier
        }

        case analysis_type
        when "conversation"
          context[:conversation_history] = options[:conversation_history] || []
        when "template"
          context[:template_type] = options[:template_type] || "general"
          context[:custom_questions] = options[:custom_questions] || []
        end

        context
      end

      def enhanced_prompt
        case analysis_type
        when "chart_analysis"
          build_chart_analysis_prompt
        when "formula_analysis"
          build_formula_analysis_prompt
        when "data_validation"
          build_data_validation_prompt
        when "conversation"
          build_conversation_prompt
        when "template"
          build_template_prompt
        else
          prompt
        end
      end

      def build_chart_analysis_prompt
        <<~PROMPT
          #{prompt}

          Please analyze this Excel chart/graph image and provide:
          1. Chart type identification
          2. Data interpretation and key insights
          3. Trend analysis
          4. Potential improvements for clarity and effectiveness
          5. Any data quality issues you notice

          Provide the response in a structured format.
        PROMPT
      end

      def build_formula_analysis_prompt
        <<~PROMPT
          #{prompt}

          Please analyze the Excel formulas shown in this image:
          1. Identify the formulas and functions being used
          2. Evaluate the logic and correctness
          3. Suggest optimizations or improvements
          4. Identify potential errors or issues
          5. Recommend alternative approaches if applicable

          Focus on accuracy and efficiency.
        PROMPT
      end

      def build_data_validation_prompt
        <<~PROMPT
          #{prompt}

          Please validate the data shown in this Excel image:
          1. Check for data consistency and patterns
          2. Identify missing or incomplete data
          3. Spot potential outliers or anomalies
          4. Assess data structure and organization
          5. Suggest data cleaning or normalization steps

          Provide specific recommendations for improvement.
        PROMPT
      end

      def build_conversation_prompt
        history_context = if options[:conversation_history]&.any?
          recent_messages = options[:conversation_history].last(3)
          "Previous conversation:\n#{recent_messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")}\n\n"
        else
          ""
        end

        "#{history_context}User question: #{prompt}\n\nPlease analyze the attached Excel image in the context of this conversation."
      end

      def build_template_prompt
        base_prompt = case options[:template_type]
        when "financial"
                       "Analyze this Excel image from a financial analysis perspective."
        when "operational"
                       "Analyze this Excel image from an operational efficiency perspective."
        when "academic"
                       "Analyze this Excel image from an academic research perspective."
        else
                       "Analyze this Excel image comprehensively."
        end

        if options[:custom_questions]&.any?
          questions = options[:custom_questions].each_with_index.map { |q, i| "#{i+1}. #{q}" }.join("\n")
          "#{base_prompt}\n\n#{prompt}\n\nAdditional questions:\n#{questions}"
        else
          "#{base_prompt}\n\n#{prompt}"
        end
      end

      def enhance_analysis_result(result)
        enhanced = result.dup
        enhanced[:analysis_type] = analysis_type
        enhanced[:confidence_score] = calculate_confidence_score(result[:content])
        enhanced[:structured_analysis] = extract_structured_data(result[:content])
        enhanced
      end

      def calculate_confidence_score(content)
        return 0.5 if content.blank?

        confidence = 0.7 # base score

        # Check for structured response
        confidence += 0.1 if content.include?("1.") || content.include?("•")

        # Check for detailed analysis
        confidence += 0.1 if content.length > 200

        # Check for Excel-specific terms
        excel_terms = %w[cell formula chart worksheet column row data]
        confidence += 0.1 if excel_terms.any? { |term| content.downcase.include?(term) }

        [ confidence, 1.0 ].min
      end

      def extract_structured_data(content)
        return {} unless content

        # Try to extract JSON blocks
        json_match = content.match(/```json\s*(\{.*?\})\s*```/m)
        return JSON.parse(json_match[1]) if json_match

        # Extract numbered points
        points = content.scan(/\d+\.\s*(.+?)(?=\d+\.|$)/m).flatten.map(&:strip)
        return { key_points: points } if points.any?

        {}
      rescue JSON::ParserError
        {}
      end

      def track_usage(result)
        @usage_tracker.track_request(
          user_id: user_id,
          provider: result[:provider],
          model: result[:model],
          credits_used: result[:credits_used],
          cost: result[:cost],
          success: true,
          features: [ "image_analysis", analysis_type ]
        )
      end

      def determine_user_tier
        User.find(user_id).subscription_tier rescue "free"
      end
    end
  end
end
