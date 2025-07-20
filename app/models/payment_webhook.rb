# == Schema Information
#
# Table name: payment_webhooks
#
#  id            :bigint           not null, primary key
#  event_type    :string
#  payment_key   :string
#  order_id      :string
#  status        :string
#  payload       :jsonb
#  processed_at  :datetime
#  error_message :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

class PaymentWebhook < ApplicationRecord
  # Event types
  EVENT_TYPES = {
    payment_status_changed: "PAYMENT_STATUS_CHANGED",
    deposit_callback: "DEPOSIT_CALLBACK",
    cancel_deposit_callback: "CANCEL_DEPOSIT_CALLBACK",
    payout_status_changed: "PAYOUT_STATUS_CHANGED"
  }.freeze

  # Validations
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES.values }
  validates :payload, presence: true

  # Scopes
  scope :unprocessed, -> { where(processed_at: nil) }
  scope :processed, -> { where.not(processed_at: nil) }
  scope :failed, -> { where.not(error_message: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def processed?
    processed_at.present?
  end

  def failed?
    error_message.present?
  end

  def process!
    return if processed?

    ActiveRecord::Base.transaction do
      case event_type
      when EVENT_TYPES[:payment_status_changed]
        process_payment_status_changed
      when EVENT_TYPES[:deposit_callback]
        process_deposit_callback
      when EVENT_TYPES[:cancel_deposit_callback]
        process_cancel_deposit_callback
      when EVENT_TYPES[:payout_status_changed]
        process_payout_status_changed
      end

      update!(processed_at: Time.current)
    end
  rescue StandardError => e
    update!(error_message: e.message)
    Rails.logger.error "Payment webhook processing failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def process_payment_status_changed
    payment_data = payload["data"]
    return unless payment_data

    payment = Payment.find_by(order_id: payment_data["orderId"])
    return unless payment

    case payment_data["status"]
    when "DONE"
      payment.mark_as_approved!(Time.parse(payment_data["approvedAt"]))
    when "CANCELED", "PARTIAL_CANCELED"
      payment.mark_as_canceled!(Time.parse(payment_data["canceledAt"]))
    when "ABORTED", "EXPIRED"
      payment.mark_as_failed!(
        payment_data["failure"]["code"],
        payment_data["failure"]["message"]
      )
    else
      payment.update!(status: payment_data["status"])
    end
  end

  def process_deposit_callback
    # Virtual account deposit confirmation
    Rails.logger.info "Processing deposit callback: #{payload}"
  end

  def process_cancel_deposit_callback
    # Virtual account deposit cancellation
    Rails.logger.info "Processing cancel deposit callback: #{payload}"
  end

  def process_payout_status_changed
    # Payout status update
    Rails.logger.info "Processing payout status changed: #{payload}"
  end
end
