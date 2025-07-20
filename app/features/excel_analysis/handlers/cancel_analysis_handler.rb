# frozen_string_literal: true

module ExcelAnalysis
  module Handlers
    class CancelAnalysisHandler < Common::BaseHandler
      def initialize(excel_file:, user:)
        @excel_file = excel_file
        @user = user
      end

      def execute
        # Validate user owns the file
        unless @excel_file.user == @user
          return Common::Result.failure(
            Common::Errors::AuthorizationError.new(
              message: "You don't have permission to cancel this analysis"
            )
          )
        end

        # Check if analysis can be cancelled
        unless can_cancel_analysis?
          return Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Analysis cannot be cancelled in current state: #{@excel_file.status}",
              code: "CANNOT_CANCEL"
            )
          )
        end

        begin
          # Cancel the analysis
          cancel_analysis

          Rails.logger.info("Analysis cancelled for file #{@excel_file.id} by user #{@user.id}")

          Common::Result.success({
            message: "Analysis cancelled successfully"
          })
        rescue StandardError => e
          Rails.logger.error("Failed to cancel analysis: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to cancel analysis: #{e.message}",
              code: "CANCEL_ERROR"
            )
          )
        end
      end

      private

      def can_cancel_analysis?
        %w[uploaded processing].include?(@excel_file.status)
      end

      def cancel_analysis
        # Update file status
        @excel_file.update!(status: "cancelled")

        # Cancel any pending background jobs
        cancel_background_jobs

        # Broadcast cancellation to WebSocket subscribers
        broadcast_cancellation

        # Refund tokens if analysis hasn't started
        refund_tokens_if_applicable
      end

      def cancel_background_jobs
        # Find and cancel any pending ExcelAnalysisJob for this file
        # This is a simplified version - in production you'd want more sophisticated job management

        # For Solid Queue, we'd need to implement job cancellation
        # For now, we'll just update the status and let the job handle it
        Rails.logger.info("Cancelling background jobs for file #{@excel_file.id}")
      end

      def broadcast_cancellation
        ActionCable.server.broadcast(
          "excel_analysis_#{@excel_file.id}",
          {
            type: "cancelled",
            message: "Analysis has been cancelled",
            status: @excel_file.status,
            timestamp: Time.current
          }
        )
      end

      def refund_tokens_if_applicable
        # Only refund if analysis hasn't actually started processing
        if @excel_file.status == "uploaded" || @excel_file.analyses.empty?
          # Refund the base cost (10 tokens)
          @user.increment!(:credits, 10)

          Rails.logger.info("Refunded 10 tokens to user #{@user.id} for cancelled analysis")
        end
      end
    end
  end
end
