# frozen_string_literal: true

module ExcelAnalysis
  module Handlers
    class AnalyzeExcelHandler < Common::BaseHandler
      def initialize(excel_file:, user:, tier: nil)
        @excel_file = excel_file
        @user = user
        @tier = tier || determine_optimal_tier
      end

      def execute
        return failure("File not found") unless @excel_file
        return failure("File not ready for analysis") unless @excel_file.can_be_analyzed?
        return failure("Insufficient tokens") unless @user.can_use_ai_tier?(@tier)

        # Update file status to processing
        @excel_file.update!(status: "processing")

        # Broadcast progress update
        broadcast_progress("Starting Excel analysis...", 10)

        begin
          # Step 1: Extract and analyze file structure
          file_data = extract_file_data
          broadcast_progress("File structure analyzed", 25)

          # Step 2: Detect errors using rule-based system
          detected_errors = detect_errors(file_data)
          broadcast_progress("Errors detected: #{detected_errors.count}", 40)

          # Step 3: FormulaEngine analysis (new)
          formula_analysis = perform_formula_analysis
          broadcast_progress("Formula analysis completed", 55)

          # Step 4: AI analysis
          ai_analysis = perform_ai_analysis(file_data, detected_errors)
          broadcast_progress("AI analysis completed", 75)

          # Step 5: Save results
          analysis = save_analysis_results(detected_errors, ai_analysis, formula_analysis)
          broadcast_progress("Analysis saved", 90)

          # Step 6: Update file status
          @excel_file.update!(status: "analyzed")
          broadcast_progress("Analysis complete", 100)

          success({
            message: "Analysis completed successfully",
            analysis_id: analysis.id,
            errors_found: detected_errors.count,
            ai_tier_used: ai_analysis[:tier_used],
            credits_used: ai_analysis[:credits_used],
            formula_count: formula_analysis&.dig(:formula_count) || 0,
            formula_complexity_score: formula_analysis&.dig(:formula_complexity_score) || 0.0
          })
        rescue => e
          @excel_file.update!(status: "failed")
          broadcast_progress("Analysis failed: #{e.message}", 0)
          failure("Analysis failed: #{e.message}")
        end
      end

      private

      attr_reader :excel_file, :user, :tier

      def determine_optimal_tier
        # Use tier 1 for basic users, tier 2 for pro+ users with complex files
        if @user.pro? || @user.enterprise?
          @excel_file.file_size > 10.megabytes ? 2 : 1
        else
          1
        end
      end

      def extract_file_data
        # Use optimized processor for better performance
        processor = ExcelAnalysis::Services::OptimizedExcelProcessor.new(@excel_file.file_path)
        result = processor.process_file

        # Log performance metrics
        if result[:performance_metrics]
          Rails.logger.info(
            "Excel processing performance: " \
            "#{result[:performance_metrics][:processing_strategy]} strategy, " \
            "#{result[:performance_metrics][:processing_time_seconds]}s, " \
            "#{result[:performance_metrics][:throughput_mb_per_second]} MB/s"
          )
        end

        result
      rescue StandardError => e
        Rails.logger.error("Optimized processing failed, falling back to standard analyzer: #{e.message}")
        # Fallback to original analyzer
        analyzer = ExcelAnalysis::Services::FileAnalyzer.new(@excel_file.file_path)
        analyzer.extract_data
      end

      def detect_errors(file_data)
        # Use errors from optimized processor if available
        if file_data[:errors]
          Rails.logger.info("Using errors from optimized processor: #{file_data[:errors].count} errors found")
          file_data[:errors]
        else
          # Fallback to separate error detection
          detector = ExcelAnalysis::Services::ErrorDetector.new(file_data)
          detector.detect_all_errors
        end
      end

      # FormulaEngine을 사용한 수식 분석 수행
      def perform_formula_analysis
        return {} unless formula_engine_available?

        Rails.logger.info("Starting FormulaEngine analysis for file: #{@excel_file.id}")

        formula_service = ExcelAnalysis::Services::FormulaAnalysisService.new(@excel_file)
        result = formula_service.analyze

        if result.success?
          Rails.logger.info("FormulaEngine analysis completed: #{result.value[:formula_count]} formulas analyzed")
          result.value
        else
          Rails.logger.warn("FormulaEngine analysis failed: #{result.error.message}")
          broadcast_progress("Formula analysis skipped: #{result.error.message}", nil)
          {}
        end
      rescue StandardError => e
        Rails.logger.error("FormulaEngine analysis error: #{e.message}")
        broadcast_progress("Formula analysis failed: #{e.message}", nil)
        {}
      end

      # FormulaEngine 서비스 가용성 확인
      def formula_engine_available?
        health_result = FormulaEngineClient.health_check

        if health_result.success?
          Rails.logger.debug("FormulaEngine health check passed")
          true
        else
          Rails.logger.warn("FormulaEngine unavailable: #{health_result.error.message}")
          false
        end
      rescue StandardError => e
        Rails.logger.warn("FormulaEngine health check failed: #{e.message}")
        false
      end

      def perform_ai_analysis(file_data, errors)
        # Use modernized multi-provider service with intelligent routing
        ai_service = AiIntegration::Services::ModernizedMultiProviderService.new(
          tier: @tier,
          enable_intelligent_routing: true
        )

        begin
          # Enhanced file metadata for better analysis
          enhanced_file_data = {
            name: @excel_file.original_name,
            size: @excel_file.file_size,
            format: File.extname(@excel_file.original_name).downcase.delete("."),
            has_vba: detect_vba_presence(file_data),
            pivot_table_count: count_pivot_tables(file_data)
          }

          Rails.logger.info("Starting AI analysis with #{errors.count} errors using modernized service")

          # Use intelligent routing for optimal tier selection
          result = ai_service.analyze_with_intelligent_routing(
            file_data: enhanced_file_data,
            user: @user,
            errors: errors
          )

          # Consume tokens based on actual usage
          tokens_consumed = result[:total_credits_used] || result[:credits_used] || 0
          @user.consume_tokens!(tokens_consumed)

          Rails.logger.info(
            "AI analysis completed: tier #{result[:tier_used]}, " \
            "confidence #{result[:confidence_score]}, " \
            "routing: #{result[:routing_method]}, " \
            "tokens: #{tokens_consumed}"
          )

          {
            analysis: result[:message],
            structured_analysis: result[:structured_analysis],
            tier_used: result[:tier_used],
            confidence_score: result[:confidence_score],
            credits_used: tokens_consumed,
            provider: result[:provider],
            routing_method: result[:routing_method],
            processing_time: result[:processing_time]
          }
        rescue StandardError => e
          Rails.logger.error("Modernized AI analysis failed, falling back to standard service: #{e.message}")

          # Fallback to original service
          fallback_ai_analysis(file_data, errors)
        end
      end

      def fallback_ai_analysis(file_data, errors)
        # Fallback to original multi-provider service
        tier1_service = AiIntegration::Services::MultiProviderService.new(tier: 1)
        tier1_result = tier1_service.analyze_excel(
          file_data: {
            name: @excel_file.original_name,
            size: @excel_file.file_size
          },
          user: @user,
          errors: errors
        )

        # Check if we need tier 2 analysis
        if tier1_result[:confidence_score] < 0.85 && @user.can_use_ai_tier?(2)
          broadcast_progress("Escalating to advanced AI analysis...", 60)

          tier2_service = AiIntegration::Services::MultiProviderService.new(tier: 2)
          tier2_result = tier2_service.analyze_excel(
            file_data: {
              name: @excel_file.original_name,
              size: @excel_file.file_size
            },
            user: @user,
            errors: errors
          )

          # Consume tokens for both tiers
          total_tokens = tier1_result[:credits_used] + tier2_result[:credits_used]
          @user.consume_tokens!(total_tokens)

          {
            analysis: tier2_result[:message],
            structured_analysis: tier2_result[:structured_analysis],
            tier_used: 2,
            confidence_score: tier2_result[:confidence_score],
            credits_used: total_tokens,
            provider: tier2_result[:provider],
            routing_method: "fallback_escalation"
          }
        else
          # Use tier 1 result
          @user.consume_tokens!(tier1_result[:credits_used])

          {
            analysis: tier1_result[:message],
            structured_analysis: tier1_result[:structured_analysis],
            tier_used: 1,
            confidence_score: tier1_result[:confidence_score],
            credits_used: tier1_result[:credits_used],
            provider: tier1_result[:provider],
            routing_method: "fallback_tier1"
          }
        end
      end

      def detect_vba_presence(file_data)
        # Check for VBA/macro indicators in file data
        return false unless file_data.is_a?(Hash)

        if file_data[:worksheets]
          file_data[:worksheets].any? do |worksheet|
            worksheet[:data]&.any? { |row| row.to_s.include?("VBA") || row.to_s.include?("Macro") } ||
            worksheet[:formulas]&.any? { |formula| formula[:formula]&.include?("VBA") }
          end
        else
          false
        end
      end

      def count_pivot_tables(file_data)
        # Count pivot table indicators in file data
        return 0 unless file_data.is_a?(Hash) && file_data[:worksheets]

        file_data[:worksheets].sum do |worksheet|
          next 0 unless worksheet[:data]

          worksheet[:data].to_s.scan(/pivot|PivotTable/i).count +
          (worksheet[:metadata]&.dig(:pivot_tables) || 0)
        end
      end

      def save_analysis_results(errors, ai_analysis, formula_analysis = {})
        analysis_data = {
          excel_file: @excel_file,
          user: @user,
          detected_errors: errors,
          ai_analysis: ai_analysis[:analysis],
          structured_analysis: ai_analysis[:structured_analysis],
          ai_tier_used: ai_analysis[:tier_used],
          confidence_score: ai_analysis[:confidence_score],
          credits_used: ai_analysis[:credits_used],
          provider: ai_analysis[:provider],
          status: "completed"
        }

        # FormulaEngine 분석 결과 추가
        if formula_analysis.present?
          analysis_data.merge!({
            formula_analysis: formula_analysis[:formula_analysis],
            formula_complexity_score: formula_analysis[:formula_complexity_score],
            formula_count: formula_analysis[:formula_count],
            formula_functions: formula_analysis[:formula_functions],
            formula_dependencies: formula_analysis[:formula_dependencies],
            circular_references: formula_analysis[:circular_references],
            formula_errors: formula_analysis[:formula_errors],
            formula_optimization_suggestions: formula_analysis[:formula_optimization_suggestions]
          })
        end

        Analysis.create!(analysis_data)
      end

      def broadcast_progress(message, percentage)
        ActionCable.server.broadcast(
          "excel_analysis_#{@excel_file.id}",
          {
            type: "progress_update",
            message: message,
            percentage: percentage,
            file_id: @excel_file.id,
            timestamp: Time.current.iso8601
          }
        )
      end
    end
  end
end
