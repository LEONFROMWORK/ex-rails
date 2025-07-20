# frozen_string_literal: true

# Solid Queue configuration
if defined?(SolidQueue)
  # Job priorities by class
  Rails.application.configure do
    config.active_job.queue_priorities = {
      "ExcelAnalysisJob" => 10,
      "AiAnalysisJob" => 8,
      "NotificationJob" => 5,
      "CleanupJob" => 2
    }
  end
end
