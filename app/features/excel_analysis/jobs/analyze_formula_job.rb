# frozen_string_literal: true

module ExcelAnalysis
  module Jobs
    class AnalyzeFormulaJob < ApplicationJob
      queue_as :default

      def perform(excel_file_id, user_id)
        excel_file = ExcelFile.find(excel_file_id)
        user = User.find(user_id)

        Rails.logger.info("Starting formula analysis for file #{excel_file_id}")

        # 토큰 확인
        return unless user.credits >= 5

        begin
          # FormulaEngine 분석 수행
          formula_service = ExcelAnalysis::Services::FormulaAnalysisService.new(excel_file)
          result = formula_service.analyze

          if result.success?
            # 기존 분석 찾기 또는 새로 생성
            analysis = excel_file.latest_analysis

            if analysis
              # 기존 분석에 FormulaEngine 결과 추가
              analysis.update!(
                formula_analysis: result.value[:formula_analysis],
                formula_complexity_score: result.value[:formula_complexity_score],
                formula_count: result.value[:formula_count],
                formula_functions: result.value[:formula_functions],
                formula_dependencies: result.value[:formula_dependencies],
                circular_references: result.value[:circular_references],
                formula_errors: result.value[:formula_errors],
                formula_optimization_suggestions: result.value[:formula_optimization_suggestions]
              )
            else
              # 새로운 분석 생성
              analysis = excel_file.analyses.create!(
                user: user,
                detected_errors: [],
                ai_tier_used: "rule_based",
                credits_used: 5,
                confidence_score: 0.9,
                status: "completed",
                formula_analysis: result.value[:formula_analysis],
                formula_complexity_score: result.value[:formula_complexity_score],
                formula_count: result.value[:formula_count],
                formula_functions: result.value[:formula_functions],
                formula_dependencies: result.value[:formula_dependencies],
                circular_references: result.value[:circular_references],
                formula_errors: result.value[:formula_errors],
                formula_optimization_suggestions: result.value[:formula_optimization_suggestions]
              )
            end

            # 토큰 차감
            user.consume_tokens!(5)

            # ActionCable로 결과 브로드캐스트
            ExcelAnalysisChannel.broadcast_to(
              excel_file,
              {
                type: "formula_analysis_complete",
                analysis_id: analysis.id,
                formula_count: result.value[:formula_count],
                complexity_score: result.value[:formula_complexity_score],
                function_count: result.value[:formula_functions]&.dig("total_functions") || 0,
                circular_ref_count: result.value[:circular_references]&.size || 0,
                error_count: result.value[:formula_errors]&.size || 0,
                suggestion_count: result.value[:formula_optimization_suggestions]&.size || 0,
                message: "수식 분석이 완료되었습니다"
              }
            )

            Rails.logger.info("Formula analysis completed for file #{excel_file_id}")

          else
            Rails.logger.error("Formula analysis failed for file #{excel_file_id}: #{result.error.message}")

            # 에러 브로드캐스트
            ExcelAnalysisChannel.broadcast_to(
              excel_file,
              {
                type: "formula_analysis_error",
                error: result.error.message
              }
            )
          end

        rescue StandardError => e
          Rails.logger.error("Formula analysis job failed for file #{excel_file_id}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))

          # 에러 브로드캐스트
          ExcelAnalysisChannel.broadcast_to(
            excel_file,
            {
              type: "formula_analysis_error",
              error: "수식 분석 중 오류가 발생했습니다: #{e.message}"
            }
          )
        end
      end
    end
  end
end
