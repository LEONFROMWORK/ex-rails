# frozen_string_literal: true

class ErrorNotificationJob < ApplicationJob
  queue_as :notifications

  def perform(job_class:, job_id:, error_message:, duration:)
    Rails.logger.error({
      event: "job_error",
      job_class: job_class,
      job_id: job_id,
      error_message: error_message,
      duration: duration,
      timestamp: Time.current
    }.to_json)

    # In production, you might want to send this to an error tracking service
    # like Sentry, Rollbar, or Bugsnag

    # For now, just log it
    Rails.logger.error("Job Error Notification: #{job_class} (#{job_id}) failed with: #{error_message}")
  end
end
