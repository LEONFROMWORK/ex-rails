class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Discard jobs that fail due to deserialization errors
  discard_on ActiveJob::DeserializationError

  # Retry network errors with exponential backoff
  retry_on Timeout::Error, wait: :exponentially_longer, attempts: 5
  retry_on Errno::ECONNRESET, wait: :exponentially_longer, attempts: 5
  retry_on Errno::ETIMEDOUT, wait: :exponentially_longer, attempts: 5

  # Performance monitoring
  around_perform do |job, block|
    start_time = Time.current

    Rails.logger.info("Job started: #{job.class.name} with args: #{job.arguments}")

    result = block.call

    duration = Time.current - start_time
    Rails.logger.info("Job completed: #{job.class.name} in #{duration.round(2)}s")

    result
  rescue => e
    duration = Time.current - start_time
    Rails.logger.error("Job failed: #{job.class.name} in #{duration.round(2)}s - #{e.message}")

    # Send error notifications in production
    if Rails.env.production?
      ErrorNotificationJob.perform_later(
        job_class: job.class.name,
        job_id: job.job_id,
        error_message: e.message,
        duration: duration
      )
    end

    raise
  end

  private

  def log_job_progress(message, progress = nil)
    log_data = {
      job_class: self.class.name,
      job_id: job_id,
      message: message
    }

    log_data[:progress] = progress if progress

    Rails.logger.info(log_data.to_json)
  end

  def broadcast_job_progress(channel, message, progress = nil)
    data = {
      type: "job_progress",
      message: message,
      timestamp: Time.current
    }

    data[:progress] = progress if progress

    ActionCable.server.broadcast(channel, data)
  end
end
