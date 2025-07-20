# frozen_string_literal: true

module Api
  module V1
    class FilesController < Api::V1::BaseController
      before_action :authenticate_user!
      before_action :find_file, only: [ :show, :destroy, :cancel, :download, :analyze, :analyze_vba, :analysis_status, :formula_analysis ]

      def index
        files = current_user.excel_files.includes(:analyses)
                           .order(created_at: :desc)
                           .page(params[:page])
                           .per(10)

        render json: {
          files: files.map { |file| serialize_file(file) },
          pagination: {
            current_page: files.current_page,
            total_pages: files.total_pages,
            total_count: files.total_count
          }
        }
      end

      def show
        render json: {
          file: serialize_file_detail(@file)
        }
      end

      def create
        handler = ExcelUpload::Handlers::ProcessUploadHandler.new(
          file: params[:file],
          user: current_user
        )

        result = handler.execute

        if result.success?
          render json: {
            file_id: result.value[:file_id],
            message: result.value[:message]
          }, status: :created
        else
          render json: {
            error: result.error.message,
            code: result.error.code
          }, status: :unprocessable_entity
        end
      end

      def destroy
        if @file.destroy
          render json: { message: "File deleted successfully" }
        else
          render json: { error: "Failed to delete file" }, status: :unprocessable_entity
        end
      end

      def cancel
        handler = ExcelAnalysis::Handlers::CancelAnalysisHandler.new(
          excel_file: @file,
          user: current_user
        )

        result = handler.execute

        if result.success?
          render json: {
            success: true,
            message: result.value[:message]
          }
        else
          render json: {
            success: false,
            message: result.error.message
          }, status: :unprocessable_entity
        end
      end

      def download
        if File.exist?(@file.file_path)
          send_file @file.file_path,
                    filename: @file.original_name,
                    type: "application/octet-stream"
        else
          render json: { error: "File not found" }, status: :not_found
        end
      end

      def analyze
        handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
          excel_file: @file,
          user: current_user,
          tier: params[:tier]
        )

        result = handler.execute

        if result.success?
          render json: {
            success: true,
            message: result.value[:message],
            analysis_id: result.value[:analysis_id],
            errors_found: result.value[:errors_found],
            ai_tier_used: result.value[:ai_tier_used],
            credits_used: result.value[:credits_used],
            formula_count: result.value[:formula_count],
            formula_complexity_score: result.value[:formula_complexity_score]
          }
        else
          render json: {
            success: false,
            error: result.error.message
          }, status: :unprocessable_entity
        end
      end

      def analyze_vba
        begin
          vba_service = ExcelAnalysis::Services::VbaAnalysisService.new(
            @file.file_path,
            deep_analysis: params[:deep_analysis] == "true",
            security_scan: params[:security_scan] == "true",
            performance_analysis: params[:performance_analysis] == "true"
          )

          result = vba_service.analyze_vba_comprehensive

          if result[:success]
            render json: {
              success: true,
              modules_found: result[:modules_found],
              static_analysis: result[:static_analysis],
              security_analysis: result[:security_analysis],
              performance_analysis: result[:performance_analysis],
              complexity_analysis: result[:complexity_analysis],
              overall_score: result[:overall_score],
              recommendations: result[:recommendations],
              processing_time: result[:processing_time]
            }
          else
            render json: {
              success: false,
              error: result[:error] || "VBA analysis failed"
            }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error("VBA analysis failed: #{e.message}")
          render json: {
            success: false,
            error: "VBA analysis failed"
          }, status: :internal_server_error
        end
      end

      def analysis_status
        analysis = @file.latest_analysis

        if analysis
          render json: {
            status: @file.status,
            analysis: serialize_analysis(analysis),
            has_vba: detect_vba_in_file(@file),
            file_info: {
              size: @file.file_size,
              name: @file.original_name,
              uploaded_at: @file.created_at
            }
          }
        else
          render json: {
            status: @file.status,
            analysis: nil,
            has_vba: detect_vba_in_file(@file),
            file_info: {
              size: @file.file_size,
              name: @file.original_name,
              uploaded_at: @file.created_at
            }
          }
        end
      end

      # FormulaEngine 전용 수식 분석 API
      def formula_analysis
        begin
          formula_service = ExcelAnalysis::Services::FormulaAnalysisService.new(@file)
          result = formula_service.analyze

          if result.success?
            # 수식 분석 결과만 반환
            formula_data = result.value

            render json: {
              success: true,
              file_id: @file.id,
              formula_analysis: {
                formula_count: formula_data[:formula_count],
                complexity_score: formula_data[:formula_complexity_score],
                complexity_level: case formula_data[:formula_complexity_score]
                                  when 0..1.0 then "Low"
                                  when 1.1..2.5 then "Medium"
                                  when 2.6..4.0 then "High"
                                  else "Very High"
                                  end,
                function_statistics: formula_data[:formula_functions],
                dependencies: formula_data[:formula_dependencies],
                circular_references: formula_data[:circular_references],
                formula_errors: formula_data[:formula_errors],
                optimization_suggestions: formula_data[:formula_optimization_suggestions],
                summary: {
                  has_formulas: formula_data[:formula_count] > 0,
                  has_circular_references: formula_data[:circular_references]&.any? || false,
                  has_formula_errors: formula_data[:formula_errors]&.any? || false,
                  needs_optimization: formula_data[:formula_optimization_suggestions]&.any? || false
                }
              }
            }
          else
            render json: {
              success: false,
              error: result.error.message,
              code: result.error.code
            }, status: :unprocessable_entity
          end
        rescue StandardError => e
          Rails.logger.error("Formula analysis API error: #{e.message}")
          render json: {
            success: false,
            error: "Formula analysis failed",
            message: e.message
          }, status: :internal_server_error
        end
      end

      private

      def find_file
        @file = current_user.excel_files.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "File not found" }, status: :not_found
      end

      def serialize_file(file)
        {
          id: file.id,
          original_name: file.original_name,
          file_size: file.file_size,
          status: file.status,
          created_at: file.created_at,
          updated_at: file.updated_at,
          analysis_count: file.analyses.count,
          latest_analysis: file.latest_analysis ? serialize_analysis(file.latest_analysis) : nil
        }
      end

      def serialize_file_detail(file)
        {
          id: file.id,
          original_name: file.original_name,
          file_size: file.file_size,
          status: file.status,
          created_at: file.created_at,
          updated_at: file.updated_at,
          analyses: file.analyses.recent.map { |analysis| serialize_analysis(analysis) }
        }
      end

      def serialize_analysis(analysis)
        base_data = {
          id: analysis.id,
          ai_tier_used: analysis.ai_tier_used,
          credits_used: analysis.credits_used,
          detected_errors: analysis.detected_errors,
          ai_analysis: analysis.ai_analysis,
          created_at: analysis.created_at
        }

        # FormulaEngine 분석 결과 추가
        if analysis.has_formula_analysis?
          base_data.merge!({
            formula_analysis: {
              formula_count: analysis.formula_count,
              complexity_score: analysis.formula_complexity_score,
              complexity_level: analysis.formula_complexity_level,
              most_used_functions: analysis.most_used_functions,
              has_circular_references: analysis.has_circular_references?,
              circular_reference_count: analysis.circular_reference_count,
              formula_error_count: analysis.formula_error_count,
              optimization_suggestion_count: analysis.optimization_suggestion_count,
              formula_functions: analysis.formula_functions,
              formula_dependencies: analysis.formula_dependencies,
              circular_references: analysis.circular_references,
              formula_errors: analysis.formula_errors,
              formula_optimization_suggestions: analysis.formula_optimization_suggestions
            }
          })
        end

        base_data
      end

      def detect_vba_in_file(file)
        # Simple VBA detection based on file extension and size
        return false unless file.original_name

        # Excel files with macros typically have specific extensions
        macro_extensions = %w[.xlsm .xltm .xlam]
        has_macro_extension = macro_extensions.any? { |ext| file.original_name.downcase.include?(ext) }

        # Also check if file size suggests complex content (rough heuristic)
        potentially_has_macros = file.file_size > 50.kilobytes

        has_macro_extension || potentially_has_macros
      end
    end
  end
end
