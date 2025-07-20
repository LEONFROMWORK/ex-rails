# frozen_string_literal: true

namespace :jobs do
  desc "Start Solid Queue worker"
  task start_worker: :environment do
    puts "Starting Solid Queue worker..."
    SolidQueue::Worker.new.start
  end

  desc "Stop all Solid Queue workers"
  task stop_workers: :environment do
    puts "Stopping all Solid Queue workers..."
    # This would require implementing a worker management system
    # For now, just output instructions
    puts "Please stop workers manually or use process management tools"
  end

  desc "Show job statistics"
  task stats: :environment do
    puts "\n=== Job Statistics ==="
    puts "Queued jobs: #{SolidQueue::Job.where(finished_at: nil).count}"
    puts "Completed jobs: #{SolidQueue::Job.where.not(finished_at: nil).count}"
    puts "Failed jobs: #{SolidQueue::Job.where.not(error: nil).count}"

    puts "\n=== Queue Statistics ==="
    SolidQueue::Job.where(finished_at: nil).group(:queue_name).count.each do |queue, count|
      puts "#{queue}: #{count} jobs"
    end

    puts "\n=== Recent Job Classes ==="
    SolidQueue::Job.order(created_at: :desc).limit(10).pluck(:class_name).each do |class_name|
      puts "- #{class_name}"
    end
  end

  desc "Cleanup old completed jobs"
  task cleanup: :environment do
    puts "Cleaning up old completed jobs..."

    # Clean up jobs older than 1 week
    old_jobs = SolidQueue::Job.where("finished_at < ?", 1.week.ago)
    count = old_jobs.count
    old_jobs.delete_all

    puts "Deleted #{count} old completed jobs"
  end

  desc "Retry failed jobs"
  task retry_failed: :environment do
    puts "Retrying failed jobs..."

    failed_jobs = SolidQueue::Job.where.not(error: nil)
    count = failed_jobs.count

    failed_jobs.each do |job|
      begin
        job.update!(error: nil, attempts: 0)
        puts "Retrying job: #{job.class_name} (#{job.id})"
      rescue => e
        puts "Failed to retry job #{job.id}: #{e.message}"
      end
    end

    puts "Queued #{count} failed jobs for retry"
  end

  desc "Schedule recurring cleanup job"
  task schedule_cleanup: :environment do
    puts "Scheduling recurring cleanup job..."

    # Schedule cleanup to run every 6 hours
    CleanupJob.set(wait: 6.hours).perform_later("all")

    puts "Cleanup job scheduled"
  end
end
