# frozen_string_literal: true

module Api
  module V1
    class PaymentWebhooksController < ActionController::API
      skip_before_action :verify_authenticity_token
      before_action :verify_webhook_signature

      # POST /api/v1/payment_webhooks
      def create
        result = PaymentWebhookService.process(webhook_params)

        if result[:success]
          head :ok
        else
          Rails.logger.error "Webhook processing failed: #{result[:error]}"
          head :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error "Webhook error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        head :internal_server_error
      end

      private

      def verify_webhook_signature
        signature = request.headers["Toss-Webhook-Signature"]
        payload = request.raw_post

        service = PaymentService.new
        unless service.verify_webhook(signature: signature, body: payload)
          Rails.logger.warn "Invalid webhook signature"
          head :unauthorized
        end
      rescue StandardError => e
        Rails.logger.error "Webhook verification error: #{e.message}"
        head :unauthorized
      end

      def webhook_params
        params.permit!.to_h
      end
    end
  end
end
