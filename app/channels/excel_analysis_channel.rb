# frozen_string_literal: true

class ExcelAnalysisChannel < ApplicationCable::Channel
  def subscribed
    # Ensure user is authenticated
    return reject unless current_user

    file_id = params[:file_id]
    return reject unless file_id.present?

    # Find and authorize file access
    excel_file = find_and_authorize_file(file_id)
    return reject unless excel_file

    # Store file reference for later use
    @excel_file = excel_file

    # Subscribe to the file's analysis stream
    stream_from "excel_analysis_#{file_id}"

    # Send current status
    transmit({
      type: "status",
      status: excel_file.status,
      analysis: excel_file.latest_analysis&.as_json(
        except: [ :raw_response, :internal_metadata ]
      ),
      user_tokens: current_user.credits,
      can_analyze: can_user_analyze?(excel_file)
    })

    Rails.logger.info("User #{current_user.id} subscribed to Excel analysis for file #{file_id}")
  end

  def unsubscribed
    Rails.logger.info("User #{current_user&.id} unsubscribed from Excel analysis for file #{@excel_file&.id}")

    # Cleanup when channel is unsubscribed
    @excel_file = nil
  end

  def request_analysis(data)
    return reject_with_error("Not authenticated") unless current_user
    return reject_with_error("Invalid file") unless @excel_file

    # Re-authorize file access
    unless can_user_analyze?(@excel_file)
      return reject_with_error("Insufficient permissions or tokens")
    end

    # Use the proper handler for analysis
    handler = ExcelAnalysis::Handlers::AnalyzeExcelHandler.new(
      excel_file: @excel_file,
      user: current_user
    )

    result = handler.execute

    if result.success?
      transmit({
        type: "queued",
        message: result.value[:message],
        tokens_remaining: current_user.reload.credits
      })
    else
      transmit({
        type: "error",
        message: result.error.message,
        error_code: result.error.code
      })
    end
  end

  def get_analysis_status(data)
    return reject_with_error("Not authenticated") unless current_user
    return reject_with_error("Invalid file") unless @excel_file

    latest_analysis = @excel_file.latest_analysis

    transmit({
      type: "analysis_status",
      status: @excel_file.status,
      analysis: latest_analysis&.as_json(
        except: [ :raw_response, :internal_metadata ]
      ),
      progress: calculate_progress(@excel_file),
      estimated_completion: estimate_completion_time(@excel_file)
    })
  end

  private

  def find_and_authorize_file(file_id)
    # Find file and ensure user owns it
    excel_file = current_user.excel_files.find_by(id: file_id)
    return nil unless excel_file

    # Additional authorization checks
    return nil unless file_accessible?(excel_file)

    excel_file
  end

  def file_accessible?(excel_file)
    # Check if file exists on filesystem
    return false unless File.exist?(excel_file.file_path)

    # Check if file is not corrupted
    return false if excel_file.status == "corrupted"

    # Check user has access to file type
    return false unless valid_file_type?(excel_file)

    true
  end

  def valid_file_type?(excel_file)
    allowed_extensions = %w[.xlsx .xls .xlsb .xlsm .xltx .xlt .xltm .ods .csv]
    file_extension = File.extname(excel_file.original_name).downcase
    allowed_extensions.include?(file_extension)
  end

  def can_user_analyze?(excel_file)
    # Check if user has sufficient tokens
    return false if current_user.credits < 10

    # Check if file is in a state that can be analyzed
    return false unless excel_file.uploaded? || excel_file.analyzed?

    # Check if user's tier allows analysis
    return false unless user_tier_allows_analysis?

    true
  end

  def user_tier_allows_analysis?
    return true unless Rails.application.config.features[:subscription_required]

    # Free tier users have limitations
    if current_user.free?
      # Limit to 5 analyses per day
      daily_analyses = current_user.analyses.where(created_at: 1.day.ago..Time.current).count
      return daily_analyses < 5
    end

    true
  end

  def calculate_progress(excel_file)
    case excel_file.status
    when "uploaded"
      0
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

  def estimate_completion_time(excel_file)
    return nil unless excel_file.processing?

    # Simple estimation based on file size
    file_size_mb = excel_file.file_size / 1.megabyte
    base_time = 10 # seconds
    size_factor = [ file_size_mb * 2, 60 ].min # Max 60 seconds additional

    base_time + size_factor
  end

  def reject_with_error(message)
    transmit({
      type: "error",
      message: message
    })

    reject
  end
end
