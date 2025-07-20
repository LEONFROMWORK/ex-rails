# frozen_string_literal: true

class PaymentIntent < ApplicationRecord
  belongs_to :user
  has_many :payments, dependent: :destroy

  validates :order_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payment_type, presence: true, inclusion: { in: %w[token_purchase subscription] }
  validates :status, presence: true

  enum :status, {
    created: "created",
    pending: "pending",
    completed: "completed",
    failed: "failed",
    canceled: "canceled",
    expired: "expired"
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_payment_type, ->(type) { where(payment_type: type) }

  def token_amount
    return 0 unless payment_type == "token_purchase"

    # 100 KRW = 1 token
    (amount / 100).to_i
  end

  def subscription_tier
    return nil unless payment_type == "subscription"

    case amount
    when 9_900..29_899
      "pro"
    when 29_900..Float::INFINITY
      "enterprise"
    else
      "basic"
    end
  end

  def expired?
    created_at < 1.hour.ago && !completed?
  end

  def can_be_canceled?
    created? || pending?
  end

  def display_name
    case payment_type
    when "token_purchase"
      "토큰 #{token_amount}개 구매"
    when "subscription"
      "#{subscription_tier&.upcase} 구독"
    else
      "결제"
    end
  end

  def self.cleanup_expired
    where(status: [ "created", "pending" ])
      .where("created_at < ?", 1.hour.ago)
      .update_all(status: "expired")
  end
end
