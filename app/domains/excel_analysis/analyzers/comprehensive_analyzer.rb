# frozen_string_literal: true

module ExcelAnalysis
  module Analyzers
    # Comprehensive Excel analyzer
    # Follows Single Responsibility Principle (SRP) and Open/Closed Principle (OCP)
    class ComprehensiveAnalyzer
      include ExcelAnalysis::Contracts::Analyzer

      def initialize(dependencies = {})
        @error_detector = dependencies[:error_detector] || ExcelAnalysis::Services::ErrorDetector.new
        @structure_analyzer = dependencies[:structure_analyzer] || ExcelAnalysis::Services::StructureAnalyzer.new
        @formula_analyzer = dependencies[:formula_analyzer] || ExcelAnalysis::Services::FormulaAnalyzer.new
        @ai_enhancer = dependencies[:ai_enhancer] || AiIntegration::Services::AnalysisEnhancer.new
      end

      private

      # Comprehensive analysis combining multiple analyzers
      # Follows Dependency Inversion Principle (DIP)
      def perform_analysis(file_path, options)
        results = {}

        # Basic structure analysis
        structure_result = @structure_analyzer.analyze(file_path)
        return structure_result if structure_result.failure?
        results[:structure] = structure_result.value

        # Error detection
        error_result = @error_detector.detect_errors(file_path, results[:structure])
        return error_result if error_result.failure?
        results[:errors] = error_result.value

        # Formula analysis
        formula_result = @formula_analyzer.analyze_formulas(file_path, results[:structure])
        return formula_result if formula_result.failure?
        results[:formulas] = formula_result.value

        # AI enhancement if enabled
        if options[:use_ai] && results[:errors].any?
          ai_result = @ai_enhancer.enhance_analysis(results)
          results[:ai_insights] = ai_result.value if ai_result.success?
        end

        # Generate summary
        summary = generate_comprehensive_summary(results)

        Shared::Types::Result.success(
          value: results.merge(summary: summary)
        )
      rescue => error
        Shared::Types::Result.failure(error: "Analysis failed: #{error.message}")
      end

      def generate_comprehensive_summary(results)
        {
          total_errors: results[:errors]&.count || 0,
          error_severity_distribution: calculate_severity_distribution(results[:errors]),
          formula_complexity: results[:formulas]&.dig(:complexity_score) || "unknown",
          sheets_analyzed: results[:structure]&.dig(:sheet_count) || 0,
          recommendations: generate_recommendations(results)
        }
      end

      def calculate_severity_distribution(errors)
        return {} unless errors

        errors.group_by { |error| error[:severity] }
              .transform_values(&:count)
      end

      def generate_recommendations(results)
        recommendations = []

        if results[:errors]&.any?
          critical_errors = results[:errors].select { |e| e[:severity] == "critical" }
          recommendations << "Fix #{critical_errors.count} critical errors immediately" if critical_errors.any?
        end

        if results[:formulas]&.dig(:complexity_score).to_i > 80
          recommendations << "Consider simplifying complex formulas for better maintainability"
        end

        recommendations
      end
    end
  end
end
