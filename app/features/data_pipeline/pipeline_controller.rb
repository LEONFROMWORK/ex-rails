# frozen_string_literal: true

module DataPipeline
  class PipelineController
    SUPPORTED_SOURCES = [ "stackoverflow", "reddit", "oppadu" ].freeze

    def initialize
      @pipeline_status = {}
      @collection_jobs = {}
      @error_handlers = {}
      initialize_pipeline_status
    end

    def start_collection(sources = SUPPORTED_SOURCES)
      sources = Array(sources) & SUPPORTED_SOURCES

      sources.each do |source|
        next if @pipeline_status[source][:status] == "running"

        begin
          start_source_collection(source)
          @pipeline_status[source][:status] = "running"
          @pipeline_status[source][:last_started_at] = Time.current
          @pipeline_status[source][:error_count] = 0
          Rails.logger.info("Started data collection for #{source}")
        rescue => e
          handle_source_error(source, e)
        end
      end

      @pipeline_status
    end

    def stop_collection(sources = SUPPORTED_SOURCES)
      sources = Array(sources) & SUPPORTED_SOURCES

      sources.each do |source|
        next if @pipeline_status[source][:status] == "stopped"

        begin
          stop_source_collection(source)
          @pipeline_status[source][:status] = "stopped"
          @pipeline_status[source][:last_stopped_at] = Time.current
          Rails.logger.info("Stopped data collection for #{source}")
        rescue => e
          handle_source_error(source, e)
        end
      end

      @pipeline_status
    end

    def get_pipeline_status
      @pipeline_status.deep_dup
    end

    def restart_failed_sources
      failed_sources = @pipeline_status.select { |_, status| status[:status] == "failed" }.keys

      failed_sources.each do |source|
        if can_restart_source?(source)
          Rails.logger.info("Restarting failed source: #{source}")
          start_collection([ source ])
        end
      end
    end

    def health_check
      {
        total_sources: SUPPORTED_SOURCES.count,
        running_sources: @pipeline_status.count { |_, status| status[:status] == "running" },
        failed_sources: @pipeline_status.count { |_, status| status[:status] == "failed" },
        stopped_sources: @pipeline_status.count { |_, status| status[:status] == "stopped" },
        overall_health: calculate_overall_health,
        sources: @pipeline_status.deep_dup
      }
    end

    private

    def initialize_pipeline_status
      SUPPORTED_SOURCES.each do |source|
        @pipeline_status[source] = {
          status: "stopped",
          last_started_at: nil,
          last_stopped_at: nil,
          last_success_at: nil,
          error_count: 0,
          last_error: nil,
          collected_items: 0,
          collection_rate: 0.0
        }
      end
    end

    def start_source_collection(source)
      case source
      when "stackoverflow"
        start_stackoverflow_collection
      when "reddit"
        start_reddit_collection
      when "oppadu"
        start_oppadu_collection
      else
        raise ArgumentError, "Unknown source: #{source}"
      end
    end

    def stop_source_collection(source)
      job = @collection_jobs[source]
      return unless job

      begin
        # Cancel the job if it's running
        job.destroy if job.respond_to?(:destroy)
        @collection_jobs.delete(source)
      rescue => e
        Rails.logger.warn("Error stopping #{source} collection: #{e.message}")
      end
    end

    def start_stackoverflow_collection
      job = DataPipeline::Jobs::StackoverflowCollectionJob.perform_later(
        pipeline_controller: self,
        source: "stackoverflow"
      )
      @collection_jobs["stackoverflow"] = job
    end

    def start_reddit_collection
      job = DataPipeline::Jobs::RedditCollectionJob.perform_later(
        pipeline_controller: self,
        source: "reddit"
      )
      @collection_jobs["reddit"] = job
    end

    def start_oppadu_collection
      job = DataPipeline::Jobs::OppaduCollectionJob.perform_later(
        pipeline_controller: self,
        source: "oppadu"
      )
      @collection_jobs["oppadu"] = job
    end

    def handle_source_error(source, error)
      @pipeline_status[source][:status] = "failed"
      @pipeline_status[source][:last_error] = error.message
      @pipeline_status[source][:error_count] += 1

      Rails.logger.error("Error in #{source} collection: #{error.message}")
      Rails.logger.error(error.backtrace.join("\n"))

      # Notify other systems about the failure
      notify_source_failure(source, error)

      # Attempt automatic recovery if error count is low
      if @pipeline_status[source][:error_count] <= 3
        Rails.logger.info("Scheduling automatic retry for #{source}")
        DataPipeline::Jobs::RetrySourceCollectionJob.perform_later(source, delay: 60.seconds)
      end
    end

    def can_restart_source?(source)
      status = @pipeline_status[source]
      return false if status[:error_count] > 5

      # Wait at least 5 minutes before retrying
      return false if status[:last_stopped_at] && status[:last_stopped_at] > 5.minutes.ago

      true
    end

    def calculate_overall_health
      running_count = @pipeline_status.count { |_, status| status[:status] == "running" }
      total_count = SUPPORTED_SOURCES.count

      case running_count
      when total_count
        "healthy"
      when 0
        "critical"
      else
        "degraded"
      end
    end

    def notify_source_failure(source, error)
      # Send notification to administrators
      # This could be email, Slack, etc.
      Rails.logger.info("Notifying administrators about #{source} failure")
    end

    # Callback methods for collection jobs
    def on_collection_success(source, items_collected)
      @pipeline_status[source][:last_success_at] = Time.current
      @pipeline_status[source][:collected_items] += items_collected
      @pipeline_status[source][:error_count] = 0

      update_collection_rate(source, items_collected)

      Rails.logger.info("#{source} collection success: #{items_collected} items")
    end

    def on_collection_failure(source, error)
      handle_source_error(source, error)
    end

    def update_collection_rate(source, items_collected)
      # Calculate collection rate (items per minute)
      time_diff = Time.current - (@pipeline_status[source][:last_started_at] || Time.current)
      rate = time_diff > 0 ? (items_collected / time_diff) * 60 : 0

      @pipeline_status[source][:collection_rate] = rate.round(2)
    end
  end
end
