# frozen_string_literal: true

class PaymentWebhookService
  def self.process(webhook_data)
    new.process(webhook_data)
  end

  def process(webhook_data)
    event_type = webhook_data["eventType"]
    data = webhook_data["data"]

    Rails.logger.info "Processing webhook: #{event_type}"

    webhook = PaymentWebhook.create!(
      event_type: event_type,
      payment_key: data["paymentKey"],
      order_id: data["orderId"],
      status: data["status"],
      payload: webhook_data
    )

    begin
      webhook.process!
      { success: true, webhook_id: webhook.id }
    rescue StandardError => e
      Rails.logger.error "Webhook processing failed: #{e.message}"
      { success: false, error: e.message, webhook_id: webhook.id }
    end
  end
end
