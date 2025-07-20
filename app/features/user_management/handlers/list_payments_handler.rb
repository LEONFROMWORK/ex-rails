# frozen_string_literal: true

module UserManagement
  module Handlers
    class ListPaymentsHandler < Common::BaseHandler
      def initialize(user:, page: 1, per_page: 10)
        @user = user
        @page = page
        @per_page = per_page
      end

      def execute
        begin
          payments = @user.payment_history
                          .page(@page)
                          .per(@per_page)

          Rails.logger.info("Retrieved #{payments.count} payments for user #{@user.id}")

          Common::Result.success({
            payments: payments,
            total_count: payments.total_count,
            current_page: @page,
            per_page: @per_page,
            total_pages: payments.total_pages
          })
        rescue StandardError => e
          Rails.logger.error("Failed to retrieve payments: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to retrieve payment history",
              code: "PAYMENT_RETRIEVAL_ERROR"
            )
          )
        end
      end
    end
  end
end
