# frozen_string_literal: true

module Shared
  module Contracts
    # Command pattern interface for all business operations
    # Follows Interface Segregation Principle (ISP)
    class Command
      include ActiveModel::Validations

      # Template method pattern - defines the algorithm structure
      def call
        validate!

        begin
          execute
        rescue => error
          handle_error(error)
        end
      end

      private

      # Abstract method - must be implemented by subclasses
      # Follows Open/Closed Principle
      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      # Error handling with consistent interface
      def handle_error(error)
        Rails.logger.error("#{self.class.name} failed: #{error.message}")
        Result.failure(error: error.message, code: :execution_error)
      end

      # Validation hook
      def validate!
        raise ArgumentError, errors.full_messages.join(", ") if invalid?
      end
    end
  end
end
