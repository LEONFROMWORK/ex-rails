# frozen_string_literal: true

class AiFeedback < ApplicationRecord
  belongs_to :user
  belongs_to :chat_message

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :ai_tier_used, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :positive, -> { where(rating: 4..5) }
  scope :negative, -> { where(rating: 1..2) }
  scope :by_tier, ->(tier) { where(ai_tier_used: tier) }
  scope :by_provider, ->(provider) { where(provider: provider) }
end
