# frozen_string_literal: true

module AiIntegration
  module Contracts
    # Interface for AI providers
    # Follows Interface Segregation Principle (ISP) and Dependency Inversion Principle (DIP)
    module AiProvider
      extend ActiveSupport::Concern

      # Common interface for all AI providers
      def analyze(prompt:, context: {}, options: {})
        validate_input(prompt, context, options)
        perform_analysis(prompt, context, options)
      end

      def chat(message:, context: {}, options: {})
        validate_input(message, context, options)
        perform_chat(message, context, options)
      end

      def analyze_image(image_data:, prompt:, context: {}, options: {})
        validate_multimodal_input(image_data, prompt, context, options)
        perform_image_analysis(image_data, prompt, context, options)
      end

      # Provider metadata
      def provider_name
        raise NotImplementedError, "#{self.class} must implement #provider_name"
      end

      def supported_features
        raise NotImplementedError, "#{self.class} must implement #supported_features"
      end

      def cost_per_token
        raise NotImplementedError, "#{self.class} must implement #cost_per_token"
      end

      private

      # Abstract methods to be implemented by concrete providers
      def perform_analysis(prompt, context, options)
        raise NotImplementedError, "#{self.class} must implement #perform_analysis"
      end

      def perform_chat(message, context, options)
        raise NotImplementedError, "#{self.class} must implement #perform_chat"
      end

      def perform_image_analysis(image_data, prompt, context, options)
        raise NotImplementedError, "#{self.class} must implement #perform_image_analysis"
      end

      # Input validation
      def validate_input(input, context, options)
        raise ArgumentError, "Input cannot be blank" if input.blank?
        raise ArgumentError, "Context must be a hash" unless context.is_a?(Hash)
        raise ArgumentError, "Options must be a hash" unless options.is_a?(Hash)
      end

      def validate_multimodal_input(image_data, prompt, context, options)
        validate_input(prompt, context, options)
        raise ArgumentError, "Image data cannot be blank" if image_data.blank?
      end
    end
  end
end
