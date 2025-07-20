# frozen_string_literal: true

module DataPipeline
  module Jobs
    class RetrySourceCollectionJob < ApplicationJob
      queue_as :data_collection

      def perform(source, delay: 0)
        # Wait for the specified delay
        sleep(delay) if delay > 0

        Rails.logger.info("Retrying data collection for source: #{source}")

        begin
          # Get the global pipeline controller instance
          pipeline_controller = DataPipeline::PipelineController.new

          # Restart the failed source
          result = pipeline_controller.start_collection([ source ])

          if result[source][:status] == "running"
            Rails.logger.info("Successfully restarted collection for #{source}")
          else
            Rails.logger.error("Failed to restart collection for #{source}")
          end

        rescue => e
          Rails.logger.error("Error retrying collection for #{source}: #{e.message}")

          # Schedule another retry with exponential backoff
          next_delay = [ delay * 2, 300 ].min # Cap at 5 minutes

          if next_delay < 300
            Rails.logger.info("Scheduling next retry for #{source} in #{next_delay} seconds")
            DataPipeline::Jobs::RetrySourceCollectionJob.perform_later(source, delay: next_delay)
          else
            Rails.logger.error("Max retry attempts reached for #{source}")
          end
        end
      end
    end
  end
end
