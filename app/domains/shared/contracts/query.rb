# frozen_string_literal: true

module Shared
  module Contracts
    # Query pattern interface for all read operations
    # Follows Interface Segregation Principle (ISP)
    class Query
      include ActiveModel::Validations

      def call
        validate!
        fetch_data
      end

      private

      # Abstract method - must be implemented by subclasses
      def fetch_data
        raise NotImplementedError, "#{self.class} must implement #fetch_data"
      end

      # Validation hook
      def validate!
        raise ArgumentError, errors.full_messages.join(", ") if invalid?
      end
    end
  end
end
