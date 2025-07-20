# frozen_string_literal: true

module ExcelAnalysis
  module Factories
    # Factory for creating analyzers
    # Follows Open/Closed Principle (OCP) and Factory Pattern
    class AnalyzerFactory
      ANALYZERS = {
        "comprehensive" => ExcelAnalysis::Analyzers::ComprehensiveAnalyzer,
        "error_detection" => ExcelAnalysis::Analyzers::ErrorDetectionAnalyzer,
        "vba_analysis" => ExcelAnalysis::Analyzers::VbaAnalyzer,
        "performance" => ExcelAnalysis::Analyzers::PerformanceAnalyzer
      }.freeze

      def create(type, dependencies = {})
        analyzer_class = ANALYZERS[type.to_s]
        raise ArgumentError, "Unknown analyzer type: #{type}" unless analyzer_class

        analyzer_class.new(dependencies)
      end

      def available_types
        ANALYZERS.keys
      end

      # Extension point for new analyzers (Open/Closed Principle)
      def register_analyzer(type, analyzer_class)
        unless analyzer_class.include?(ExcelAnalysis::Contracts::Analyzer)
          raise ArgumentError, "Analyzer must include ExcelAnalysis::Contracts::Analyzer"
        end

        ANALYZERS[type.to_s] = analyzer_class
      end
    end
  end
end
