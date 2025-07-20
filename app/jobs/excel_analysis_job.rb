# frozen_string_literal: true

class ExcelAnalysisJob < ApplicationJob
  queue_as :excel_processing

  discard_on ActiveJob::DeserializationError
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(file_id, user_id)
    excel_file = ExcelFile.find(file_id)
    user = User.find(user_id)

    Rails.logger.info("Starting Excel analysis for file #{file_id} by user #{user_id}")

    # Check if analysis was cancelled
    if excel_file.status == "cancelled"
      Rails.logger.info("Analysis cancelled for file #{file_id}")
      return
    end

    # Update status to processing
    excel_file.update!(status: "processing")
    broadcast_progress(excel_file, "Starting analysis...", 0)

    begin
      # Step 1: Excel file analysis
      broadcast_progress(excel_file, "Analyzing Excel file structure...", 10)
      analyzer = ExcelAnalysis::AnalyzeErrors::ExcelAnalyzerService.new(excel_file.file_path)
      detected_errors = analyzer.analyze

      broadcast_progress(excel_file, "Excel analysis complete. Preparing AI analysis...", 30)

      # Step 2: AI analysis
      broadcast_progress(excel_file, "Running AI analysis...", 40)
      ai_handler = AiIntegration::MultiProvider::AiAnalysisHandler.new(
        errors: detected_errors,
        user: user,
        excel_file: excel_file
      )

      ai_result = ai_handler.execute

      unless ai_result.success?
        handle_analysis_failure(excel_file, ai_result.error.message)
        return
      end

      broadcast_progress(excel_file, "AI analysis complete. Saving results...", 80)

      # Step 3: Save analysis results
      analysis = Analysis.create!(
        excel_file: excel_file,
        user: user,
        detected_errors: detected_errors,
        ai_analysis: ai_result.value[:analysis],
        ai_tier_used: ai_result.value[:tier_used],
        credits_used: ai_result.value[:credits_used],
        confidence_score: ai_result.value[:confidence_score]
      )

      # Step 4: Deduct credits from user
      user.decrement!(:credits, ai_result.value[:credits_used])

      # Step 5: Update file status
      excel_file.update!(status: "analyzed")

      broadcast_progress(excel_file, "Analysis completed successfully!", 100)

      # Broadcast completion
      broadcast_completion(excel_file, analysis)

      Rails.logger.info("Excel analysis completed for file #{file_id}")

    rescue StandardError => e
      Rails.logger.error("Excel analysis failed for file #{file_id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      handle_analysis_failure(excel_file, e.message)
    end
  end

  private

  def broadcast_progress(excel_file, message, progress)
    ActionCable.server.broadcast(
      "excel_analysis_#{excel_file.id}",
      {
        type: "progress",
        message: message,
        progress: progress,
        status: excel_file.status,
        timestamp: Time.current
      }
    )
  end

  def broadcast_completion(excel_file, analysis)
    ActionCable.server.broadcast(
      "excel_analysis_#{excel_file.id}",
      {
        type: "completed",
        message: "Analysis completed successfully",
        progress: 100,
        status: excel_file.status,
        analysis: serialize_analysis(analysis),
        timestamp: Time.current
      }
    )
  end

  def handle_analysis_failure(excel_file, error_message)
    excel_file.update!(status: "failed")

    ActionCable.server.broadcast(
      "excel_analysis_#{excel_file.id}",
      {
        type: "error",
        message: error_message,
        status: excel_file.status,
        timestamp: Time.current
      }
    )
  end

  def serialize_analysis(analysis)
    {
      id: analysis.id,
      ai_tier_used: analysis.ai_tier_used,
      credits_used: analysis.credits_used,
      confidence_score: analysis.confidence_score,
      errors_found: analysis.detected_errors&.size || 0,
      created_at: analysis.created_at
    }
  end
end
