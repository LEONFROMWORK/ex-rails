# frozen_string_literal: true

module Shared
  module Types
    # Result type for consistent return values
    # Follows Single Responsibility Principle (SRP)
    class Result
      attr_reader :value, :error, :metadata

      def initialize(success:, value: nil, error: nil, metadata: {})
        @success = success
        @value = value
        @error = error
        @metadata = metadata
        freeze
      end

      def self.success(value: nil, metadata: {})
        new(success: true, value: value, metadata: metadata)
      end

      def self.failure(error:, metadata: {})
        new(success: false, error: error, metadata: metadata)
      end

      def success?
        @success
      end

      def failure?
        !@success
      end

      def unwrap
        raise "Cannot unwrap failed result: #{error}" if failure?
        value
      end

      def unwrap_or(default)
        success? ? value : default
      end

      # Monadic operations
      def map(&block)
        return self if failure?

        begin
          new_value = block.call(value)
          self.class.success(value: new_value, metadata: metadata)
        rescue => error
          self.class.failure(error: error.message, metadata: metadata)
        end
      end

      def flat_map(&block)
        return self if failure?

        begin
          result = block.call(value)
          raise "Block must return a Result" unless result.is_a?(Result)
          result
        rescue => error
          self.class.failure(error: error.message, metadata: metadata)
        end
      end

      def to_h
        {
          success: success?,
          value: value,
          error: error,
          metadata: metadata
        }
      end
    end
  end
end
