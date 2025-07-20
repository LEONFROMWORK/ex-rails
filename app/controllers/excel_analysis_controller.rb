# frozen_string_literal: true

# Vertical Slice controller for Excel Analysis domain
# Follows Single Responsibility Principle (SRP) - only handles Excel analysis requests
class ExcelAnalysisController < ApplicationController
  before_action :authenticate_user!

  # Analyze Excel file
  def analyze
    command = ExcelAnalysis::Commands::AnalyzeExcelFile.new.tap do |cmd|
      cmd.file_id = params[:file_id]
      cmd.user_id = current_user.id
      cmd.analysis_type = params[:analysis_type] || "comprehensive"
      cmd.options = analysis_options
    end

    result = command.call

    if result.success?
      render json: {
        success: true,
        analysis_id: result.value[:analysis_id],
        summary: result.value[:summary],
        errors_found: result.value[:errors_found]
      }
    else
      render json: {
        success: false,
        error: result.error
      }, status: :unprocessable_entity
    end
  end

  # Get analysis status
  def status
    query = ExcelAnalysis::Queries::GetAnalysisStatus.new.tap do |q|
      q.file_id = params[:file_id]
      q.user_id = current_user.id
    end

    result = query.call

    if result.success?
      render json: result.value
    else
      render json: { error: result.error }, status: :not_found
    end
  end

  # VBA-specific analysis
  def analyze_vba
    command = ExcelAnalysis::Commands::AnalyzeExcelFile.new.tap do |cmd|
      cmd.file_id = params[:file_id]
      cmd.user_id = current_user.id
      cmd.analysis_type = "vba_analysis"
      cmd.options = vba_analysis_options
    end

    result = command.call

    if result.success?
      render json: {
        success: true,
        analysis: result.value
      }
    else
      render json: {
        success: false,
        error: result.error
      }, status: :unprocessable_entity
    end
  end

  private

  def analysis_options
    {
      use_ai: params[:use_ai] != "false",
      deep_analysis: params[:deep_analysis] == "true",
      tier: determine_analysis_tier
    }
  end

  def vba_analysis_options
    {
      security_scan: params[:security_scan] != "false",
      performance_analysis: params[:performance_analysis] == "true",
      deep_analysis: params[:deep_analysis] == "true"
    }
  end

  def determine_analysis_tier
    case current_user.subscription_tier
    when "enterprise" then 3
    when "pro" then 2
    else 1
    end
  end
end
