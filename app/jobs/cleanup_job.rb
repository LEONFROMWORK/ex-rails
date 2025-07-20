# frozen_string_literal: true

class CleanupJob < ApplicationJob
  queue_as :cleanup

  def perform(cleanup_type = "all")
    log_job_progress("Starting cleanup: #{cleanup_type}")

    case cleanup_type
    when "old_files"
      cleanup_old_files
    when "failed_jobs"
      cleanup_failed_jobs
    when "temp_data"
      cleanup_temp_data
    when "all"
      cleanup_old_files
      cleanup_failed_jobs
      cleanup_temp_data
    else
      Rails.logger.warn("Unknown cleanup type: #{cleanup_type}")
    end

    log_job_progress("Cleanup completed: #{cleanup_type}")
  end

  private

  def cleanup_old_files
    log_job_progress("Cleaning up old files")

    # Remove Excel files older than 30 days that are not analyzed
    old_files = ExcelFile.where(
      "created_at < ? AND status NOT IN (?)",
      30.days.ago,
      [ "analyzed", "processing" ]
    )

    old_files.find_each do |file|
      begin
        file.cleanup_file!
        file.destroy
        Rails.logger.info("Cleaned up old file: #{file.id}")
      rescue => e
        Rails.logger.error("Failed to cleanup file #{file.id}: #{e.message}")
      end
    end

    log_job_progress("Old files cleanup completed")
  end

  def cleanup_failed_jobs
    log_job_progress("Cleaning up failed jobs")

    # Reset failed Excel files older than 1 hour to allow retry
    failed_files = ExcelFile.where(
      "status = ? AND updated_at < ?",
      "failed",
      1.hour.ago
    )

    failed_files.update_all(status: "uploaded")

    Rails.logger.info("Reset #{failed_files.count} failed files for retry")

    log_job_progress("Failed jobs cleanup completed")
  end

  def cleanup_temp_data
    log_job_progress("Cleaning up temporary data")

    # Clean up temporary upload directory
    temp_dir = Rails.root.join("tmp", "uploads")
    if Dir.exist?(temp_dir)
      Dir.glob(File.join(temp_dir, "*")).each do |file|
        if File.mtime(file) < 1.day.ago
          begin
            File.delete(file)
            Rails.logger.info("Deleted temp file: #{file}")
          rescue => e
            Rails.logger.error("Failed to delete temp file #{file}: #{e.message}")
          end
        end
      end
    end

    log_job_progress("Temporary data cleanup completed")
  end
end
