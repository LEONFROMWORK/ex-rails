# frozen_string_literal: true

module AiIntegration
  module ResponseValidation
    class AiResponseValidator
      REQUIRED_FIELDS = %w[message confidence_score credits_used provider].freeze
      OPTIONAL_FIELDS = %w[structured_analysis suggestions improvements fixes].freeze

      def initialize(response, expected_type: :chat)
        @response = response
        @expected_type = expected_type
        @errors = []
      end

      def validate
        return failure_result unless @response.is_a?(Hash)

        validate_required_fields
        validate_confidence_score
        validate_token_usage
        validate_provider
        validate_message_content
        validate_structured_analysis if has_structured_analysis?

        if @errors.empty?
          Common::Result.success(cleaned_response)
        else
          Common::Result.failure(@errors)
        end
      end

      private

      def validate_required_fields
        REQUIRED_FIELDS.each do |field|
          unless @response.key?(field) || @response.key?(field.to_sym)
            @errors << "Missing required field: #{field}"
          end
        end
      end

      def validate_confidence_score
        confidence = get_field_value("confidence_score")
        return unless confidence

        unless confidence.is_a?(Numeric) && confidence >= 0 && confidence <= 1
          @errors << "Invalid confidence_score: must be a number between 0 and 1"
        end
      end

      def validate_token_usage
        tokens = get_field_value("credits_used")
        return unless tokens

        unless tokens.is_a?(Integer) && tokens > 0
          @errors << "Invalid credits_used: must be a positive integer"
        end
      end

      def validate_provider
        provider = get_field_value("provider")
        return unless provider

        valid_providers = %w[openai anthropic openrouter google cohere]
        unless valid_providers.include?(provider.to_s.downcase)
          @errors << "Invalid provider: #{provider}"
        end
      end

      def validate_message_content
        message = get_field_value("message")
        return unless message

        if message.to_s.strip.empty?
          @errors << "Message content cannot be empty"
        end

        if message.to_s.length > 50000
          @errors << "Message content too long (max 50,000 characters)"
        end

        # Check for potential harmful content patterns
        if contains_harmful_content?(message)
          @errors << "Message contains potentially harmful content"
        end
      end

      def validate_structured_analysis
        analysis = get_field_value("structured_analysis")
        return unless analysis

        unless analysis.is_a?(Hash)
          @errors << "structured_analysis must be a hash"
          return
        end

        # Validate Excel analysis specific fields
        if @expected_type == :excel_analysis
          validate_excel_analysis_structure(analysis)
        end
      end

      def validate_excel_analysis_structure(analysis)
        expected_keys = %w[errors_found warnings_found optimizations_suggested]

        expected_keys.each do |key|
          unless analysis.key?(key) || analysis.key?(key.to_sym)
            @errors << "Missing structured_analysis field: #{key}"
          end
        end

        # Validate error counts
        %w[errors_found warnings_found optimizations_suggested].each do |count_field|
          count = analysis[count_field] || analysis[count_field.to_sym]
          next unless count

          unless count.is_a?(Integer) && count >= 0
            @errors << "Invalid #{count_field}: must be a non-negative integer"
          end
        end
      end

      def contains_harmful_content?(content)
        harmful_patterns = [
          /\b(password|secret|token|key|credential)\s*[:=]\s*\S+/i,
          /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/, # Credit card patterns
          /\b\d{3}-\d{2}-\d{4}\b/, # SSN patterns
          /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi # Script tags
        ]

        harmful_patterns.any? { |pattern| content.match?(pattern) }
      end

      def has_structured_analysis?
        @response.key?("structured_analysis") || @response.key?(:structured_analysis)
      end

      def get_field_value(field_name)
        @response[field_name] || @response[field_name.to_sym]
      end

      def cleaned_response
        cleaned = {}

        # Add all valid fields
        (REQUIRED_FIELDS + OPTIONAL_FIELDS).each do |field|
          value = get_field_value(field)
          cleaned[field] = value if value
        end

        # Sanitize message content
        if cleaned["message"]
          cleaned["message"] = sanitize_message(cleaned["message"])
        end

        # Ensure confidence score is properly formatted
        if cleaned["confidence_score"]
          cleaned["confidence_score"] = cleaned["confidence_score"].to_f.round(3)
        end

        cleaned
      end

      def sanitize_message(message)
        # Remove potential harmful scripts and normalize whitespace
        sanitized = message.to_s
          .gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi, "")
          .gsub(/\s+/, " ")
          .strip

        # Truncate if too long
        sanitized.length > 10000 ? "#{sanitized[0, 10000]}..." : sanitized
      end

      def failure_result
        Common::Result.failure([ "Invalid response format: expected Hash, got #{@response.class}" ])
      end
    end
  end
end
