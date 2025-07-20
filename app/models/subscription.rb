# frozen_string_literal: true

class Subscription < ApplicationRecord
  # Associations
  belongs_to :user

  # Enums
  enum :status, { active: 0, canceled: 1, expired: 2, pending: 3 }
  enum :tier, { free: 0, basic: 1, pro: 2, enterprise: 3 }

  # Constants
  PLANS = {
    "free" => { tokens: 100, price: 0 },
    "basic" => { tokens: 500, price: 9_900 },
    "pro" => { tokens: 2_000, price: 29_900 },
    "enterprise" => { tokens: 10_000, price: 99_900 }
  }.freeze

  # Validations
  validates :plan_type, presence: true, inclusion: { in: PLANS.keys }
  validates :starts_at, presence: true
  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true

  # Scopes
  scope :active, -> { where(status: :active).where("ends_at IS NULL OR ends_at > ?", Time.current) }
  scope :expiring_soon, -> { active.where("ends_at BETWEEN ? AND ?", Time.current, 7.days.from_now) }

  # Callbacks
  before_validation :set_defaults

  # Instance methods
  def active?
    status == "active" && (ends_at.nil? || ends_at > Time.current)
  end

  def expired?
    ends_at.present? && ends_at <= Time.current
  end

  def cancel!
    update!(
      status: :canceled,
      canceled_at: Time.current,
      ends_at: Time.current.end_of_day
    )
  end

  def days_remaining
    return nil unless ends_at.present?

    ((ends_at - Time.current) / 1.day).ceil
  end

  def plan_details
    PLANS[plan_type]
  end

  def tokens_included
    plan_details[:credits]
  end

  private

  def set_defaults
    self.amount ||= plan_details[:price] if plan_type.present?
    self.currency ||= "KRW"
  end
end
