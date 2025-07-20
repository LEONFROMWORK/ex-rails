# frozen_string_literal: true

class ExcelFilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_excel_file, only: [ :show, :analyze, :download_corrected, :analyze_vba, :vba_results, :download, :analysis_results, :reanalyze, :progress, :analyze_formulas, :formula_results ]

  def index
    @excel_files = current_user.excel_files.includes(:analyses).recent.page(params[:page])
  end

  def show
    @latest_analysis = @excel_file.latest_analysis

    # FormulaEngine 분석이 아직 없다면 자동으로 수행 (단순한 분석만)
    if @latest_analysis && !@latest_analysis.has_formula_analysis? && @excel_file.analyzed?
      perform_formula_analysis_async
    end
  end

  def new
    @excel_file = current_user.excel_files.build
  end

  def create
    handler = ExcelUpload::Handlers::UploadExcelHandler.new(
      user: current_user,
      file: params[:file]
    )

    result = handler.call

    if result.success?
      redirect_to excel_file_path(result.value.file_id),
                  notice: "File uploaded successfully and queued for processing"
    else
      flash.now[:alert] = result.error.is_a?(Array) ? result.error.join(", ") : result.error.message
      render :new, status: :unprocessable_entity
    end
  end

  def analyze
    handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
      excel_file: @excel_file,
      user: current_user
    )

    result = handler.execute

    if result.success?
      redirect_to @excel_file, notice: result.value[:message]
    else
      error_message = result.error.is_a?(Common::Errors::ValidationError) ?
                     result.error.details[:errors].join(", ") :
                     result.error.message
      redirect_to @excel_file, alert: error_message
    end
  end

  def download_corrected
    handler = ExcelAnalysis::Handlers::DownloadCorrectedHandler.new(
      excel_file: @excel_file,
      user: current_user
    )

    result = handler.execute

    if result.success?
      send_data result.value[:content],
                filename: result.value[:filename],
                type: result.value[:content_type]
    else
      error_message = result.error.is_a?(Common::Errors::ValidationError) ?
                     result.error.details[:errors].join(", ") :
                     result.error.message
      redirect_to @excel_file, alert: error_message
    end
  end

  # VBA 분석 액션
  def analyze_vba
    return render json: { error: "VBA 분석을 위해서는 10토큰이 필요합니다" }, status: :payment_required unless current_user.credits >= 10

    begin
      vba_service = ExcelAnalysis::Services::VbaAnalysisService.new(@excel_file.file_path)
      result = vba_service.analyze_vba_comprehensive

      if result[:success]
        # VBA 분석 결과 저장
        vba_analysis = VbaAnalysis.create!(
          excel_file: @excel_file,
          user: current_user,
          analysis_results: result,
          modules_found: result[:modules_found],
          overall_score: result[:overall_score],
          security_risk_level: result[:security_analysis][:risk_level],
          performance_score: result[:performance_analysis][:optimization_score]
        )

        # 토큰 차감
        current_user.consume_tokens!(10)

        render json: {
          success: true,
          analysis_id: vba_analysis.id,
          modules_found: result[:modules_found],
          overall_score: result[:overall_score],
          security_analysis: result[:security_analysis],
          performance_analysis: result[:performance_analysis],
          complexity_analysis: result[:complexity_analysis],
          recommendations: result[:recommendations],
          processing_time: result[:processing_time]
        }
      else
        render json: { success: false, error: result[:error] || "VBA 분석에 실패했습니다" }, status: :unprocessable_entity
      end

    rescue StandardError => e
      Rails.logger.error("VBA analysis failed: #{e.message}")
      render json: { success: false, error: "VBA 분석 중 오류가 발생했습니다" }, status: :internal_server_error
    end
  end

  # VBA 분석 결과 조회
  def vba_results
    vba_analysis = @excel_file.vba_analyses.latest.first

    if vba_analysis
      render json: {
        success: true,
        analysis: vba_analysis.analysis_results,
        created_at: vba_analysis.created_at,
        overall_score: vba_analysis.overall_score,
        security_risk_level: vba_analysis.security_risk_level,
        performance_score: vba_analysis.performance_score
      }
    else
      render json: { success: false, error: "VBA 분석 결과를 찾을 수 없습니다" }, status: :not_found
    end
  end

  # 파일 다운로드
  def download
    if File.exist?(@excel_file.file_path)
      send_file @excel_file.file_path,
                filename: @excel_file.original_name,
                type: @excel_file.content_type,
                disposition: "attachment"
    else
      redirect_to @excel_file, alert: "파일을 찾을 수 없습니다"
    end
  end

  # 분석 결과 조회
  def analysis_results
    latest_analysis = @excel_file.analyses.latest.first

    if latest_analysis
      render json: {
        success: true,
        analysis: {
          id: latest_analysis.id,
          detected_errors: latest_analysis.detected_errors,
          ai_analysis: latest_analysis.ai_analysis,
          structured_analysis: latest_analysis.structured_analysis,
          confidence_score: latest_analysis.confidence_score,
          ai_tier_used: latest_analysis.ai_tier_used,
          credits_used: latest_analysis.credits_used,
          created_at: latest_analysis.created_at
        }
      }
    else
      render json: { success: false, error: "분석 결과를 찾을 수 없습니다" }, status: :not_found
    end
  end

  # 재분석
  def reanalyze
    # 기존 분석 핸들러 재사용
    handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
      excel_file: @excel_file,
      user: current_user
    )

    result = handler.execute

    if result.success?
      render json: {
        success: true,
        message: result.value[:message],
        analysis_id: result.value[:analysis_id]
      }
    else
      error_message = result.error.is_a?(Common::Errors::ValidationError) ?
                     result.error.details[:errors].join(", ") :
                     result.error.message
      render json: { success: false, error: error_message }, status: :unprocessable_entity
    end
  end

  # 처리 진행률 확인
  def progress
    # ActionCable을 통한 실시간 진행률은 JavaScript에서 처리
    # 여기서는 현재 상태만 반환
    render json: {
      success: true,
      status: @excel_file.status,
      file_id: @excel_file.id,
      progress_channel: "excel_analysis_#{@excel_file.id}"
    }
  end

  # FormulaEngine 분석 수행
  def analyze_formulas
    return render json: { error: "수식 분석을 위해서는 5토큰이 필요합니다" }, status: :payment_required unless current_user.credits >= 5

    begin
      formula_service = ExcelAnalysis::Services::FormulaAnalysisService.new(@excel_file)
      result = formula_service.analyze

      if result.success?
        # 기존 분석에 FormulaEngine 결과 추가
        if @latest_analysis
          @latest_analysis.update!(
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
          @latest_analysis = @excel_file.analyses.create!(
            user: current_user,
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
        current_user.consume_tokens!(5)

        render json: {
          success: true,
          analysis_id: @latest_analysis.id,
          formula_count: result.value[:formula_count],
          complexity_score: result.value[:formula_complexity_score],
          function_count: result.value[:formula_functions]&.dig("total_functions") || 0,
          circular_ref_count: result.value[:circular_references]&.size || 0,
          error_count: result.value[:formula_errors]&.size || 0,
          suggestion_count: result.value[:formula_optimization_suggestions]&.size || 0,
          message: "수식 분석이 완료되었습니다"
        }
      else
        render json: { success: false, error: result.error.message }, status: :unprocessable_entity
      end

    rescue StandardError => e
      Rails.logger.error("Formula analysis failed: #{e.message}")
      render json: { success: false, error: "수식 분석 중 오류가 발생했습니다" }, status: :internal_server_error
    end
  end

  # FormulaEngine 분석 결과 조회
  def formula_results
    if @latest_analysis&.has_formula_analysis?
      render json: {
        success: true,
        analysis: {
          formula_count: @latest_analysis.formula_count,
          complexity_score: @latest_analysis.formula_complexity_score,
          complexity_level: @latest_analysis.formula_complexity_level,
          functions: @latest_analysis.formula_functions,
          dependencies: @latest_analysis.formula_dependencies,
          circular_references: @latest_analysis.circular_references,
          errors: @latest_analysis.formula_errors,
          optimization_suggestions: @latest_analysis.formula_optimization_suggestions,
          created_at: @latest_analysis.updated_at
        }
      }
    else
      render json: { success: false, error: "수식 분석 결과를 찾을 수 없습니다" }, status: :not_found
    end
  end

  private

  def set_excel_file
    @excel_file = current_user.excel_files.find(params[:id])
  end

  # FormulaEngine 분석을 비동기로 수행
  def perform_formula_analysis_async
    return unless @excel_file.analyzed? && current_user.credits >= 5

    # 백그라운드 잡으로 수행
    ExcelAnalysis::Jobs::AnalyzeFormulaJob.perform_later(@excel_file.id, current_user.id)
  rescue StandardError => e
    Rails.logger.error("Failed to queue formula analysis: #{e.message}")
  end
end
