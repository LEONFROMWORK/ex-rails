# frozen_string_literal: true

module ExcelAnalysis
  module Contracts
    # Analyzer interface for different analysis types
    # Follows Interface Segregation Principle (ISP)
    module Analyzer
      extend ActiveSupport::Concern

      # Common interface for all analyzers
      def analyze(file_path, options = {})
        validate_file(file_path)
        perform_analysis(file_path, options)
      end

      private

      # Abstract methods to be implemented by concrete analyzers
      def perform_analysis(file_path, options)
        raise NotImplementedError, "#{self.class} must implement #perform_analysis"
      end

      def validate_file(file_path)
        raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)
        raise ArgumentError, "Invalid file format" unless valid_format?(file_path)
      end

      def valid_format?(file_path)
        %w[.xlsx .xls .xlsm].include?(File.extname(file_path).downcase)
      end
    end
  end
end
