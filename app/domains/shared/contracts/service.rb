# frozen_string_literal: true

module Shared
  module Contracts
    # Service interface for domain services
    # Follows Dependency Inversion Principle (DIP)
    module Service
      extend ActiveSupport::Concern

      included do
        include ActiveModel::Validations
        include ActiveModel::Attributes
      end

      # Common service interface
      def perform
        validate_inputs
        execute_service
      rescue => error
        handle_service_error(error)
      end

      private

      # Abstract method
      def execute_service
        raise NotImplementedError, "#{self.class} must implement #execute_service"
      end

      def validate_inputs
        raise ArgumentError, errors.full_messages.join(", ") if invalid?
      end

      def handle_service_error(error)
        Rails.logger.error("#{self.class.name} failed: #{error.message}")
        Result.failure(error: error.message, service: self.class.name)
      end
    end
  end
end
