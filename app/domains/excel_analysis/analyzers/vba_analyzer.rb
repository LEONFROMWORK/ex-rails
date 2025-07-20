# frozen_string_literal: true

module ExcelAnalysis
  module Analyzers
    # VBA-specific analyzer
    # Follows Single Responsibility Principle (SRP) - only analyzes VBA code
    class VbaAnalyzer
      include ExcelAnalysis::Contracts::Analyzer

      def initialize(dependencies = {})
        @vba_extractor = dependencies[:vba_extractor] || ExcelAnalysis::Services::VbaExtractor.new
        @vba_security_scanner = dependencies[:vba_security_scanner] || ExcelAnalysis::Services::VbaSecurityScanner.new
        @vba_performance_analyzer = dependencies[:vba_performance_analyzer] || ExcelAnalysis::Services::VbaPerformanceAnalyzer.new
      end

      private

      def perform_analysis(file_path, options)
        # Extract VBA modules
        extraction_result = @vba_extractor.extract_modules(file_path)
        return extraction_result if extraction_result.failure?

        modules = extraction_result.value
        return Shared::Types::Result.success(value: { modules_found: 0, message: "No VBA code found" }) if modules.empty?

        analysis_results = {
          modules_found: modules.count,
          modules: []
        }

        # Analyze each module
        modules.each do |module_data|
          module_analysis = analyze_module(module_data, options)
          analysis_results[:modules] << module_analysis if module_analysis
        end

        # Generate overall VBA analysis summary
        summary = generate_vba_summary(analysis_results)

        Shared::Types::Result.success(
          value: analysis_results.merge(summary: summary)
        )
      rescue => error
        Shared::Types::Result.failure(error: "VBA analysis failed: #{error.message}")
      end

      def analyze_module(module_data, options)
        module_result = {
          name: module_data[:name],
          type: module_data[:type],
          line_count: module_data[:line_count]
        }

        # Security analysis
        if options[:security_scan] != false
          security_result = @vba_security_scanner.scan_module(module_data)
          module_result[:security] = security_result.value if security_result.success?
        end

        # Performance analysis
        if options[:performance_analysis] == true
          performance_result = @vba_performance_analyzer.analyze_module(module_data)
          module_result[:performance] = performance_result.value if performance_result.success?
        end

        module_result
      end

      def generate_vba_summary(results)
        {
          total_modules: results[:modules_found],
          security_risk_level: calculate_security_risk(results[:modules]),
          performance_score: calculate_performance_score(results[:modules]),
          recommendations: generate_vba_recommendations(results[:modules])
        }
      end

      def calculate_security_risk(modules)
        risk_scores = modules.filter_map { |m| m.dig(:security, :risk_score) }
        return "unknown" if risk_scores.empty?

        avg_risk = risk_scores.sum.to_f / risk_scores.size
        case avg_risk
        when 0..3 then "low"
        when 3..7 then "medium"
        else "high"
        end
      end

      def calculate_performance_score(modules)
        perf_scores = modules.filter_map { |m| m.dig(:performance, :score) }
        return nil if perf_scores.empty?

        (perf_scores.sum.to_f / perf_scores.size).round(1)
      end

      def generate_vba_recommendations(modules)
        recommendations = []

        high_risk_modules = modules.select { |m| m.dig(:security, :risk_score).to_i > 7 }
        if high_risk_modules.any?
          recommendations << "Review #{high_risk_modules.count} high-risk VBA modules for security issues"
        end

        low_perf_modules = modules.select { |m| m.dig(:performance, :score).to_i < 60 }
        if low_perf_modules.any?
          recommendations << "Optimize #{low_perf_modules.count} VBA modules for better performance"
        end

        recommendations
      end
    end
  end
end
