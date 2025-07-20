# frozen_string_literal: true

class Excel::AnalysisProgressComponent < ViewComponent::Base
  def initialize(excel_file:, user:)
    @excel_file = excel_file
    @user = user
  end

  private

  attr_reader :excel_file, :user

  def analysis_status
    excel_file.status
  end

  def progress_percentage
    case analysis_status
    when "uploaded"
      10
    when "processing"
      50
    when "analyzed"
      100
    when "failed"
      0
    else
      0
    end
  end

  def status_message
    case analysis_status
    when "uploaded"
      "File uploaded successfully. Preparing for analysis..."
    when "processing"
      "AI is analyzing your Excel file. This may take a few minutes..."
    when "analyzed"
      "Analysis completed successfully!"
    when "failed"
      "Analysis failed. Please try again or contact support."
    else
      "Unknown status"
    end
  end

  def status_color
    case analysis_status
    when "uploaded"
      "text-blue-600"
    when "processing"
      "text-yellow-600"
    when "analyzed"
      "text-green-600"
    when "failed"
      "text-red-600"
    else
      "text-gray-600"
    end
  end

  def show_cancel_button?
    %w[uploaded processing].include?(analysis_status)
  end

  def show_retry_button?
    analysis_status == "failed"
  end

  def latest_analysis
    @latest_analysis ||= excel_file.latest_analysis
  end

  def estimated_completion_time
    return nil unless analysis_status == "processing"

    file_size_mb = excel_file.file_size / 1.megabyte
    base_time = 10
    size_factor = [ file_size_mb * 2, 60 ].min

    base_time + size_factor
  end

  def analysis_details
    return nil unless latest_analysis

    {
      tier_used: latest_analysis.ai_tier_used,
      credits_used: latest_analysis.credits_used,
      errors_found: latest_analysis.detected_errors&.count || 0,
      created_at: latest_analysis.created_at
    }
  end
end
