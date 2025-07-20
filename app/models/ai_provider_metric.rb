# frozen_string_literal: true

class AiProviderMetric < ApplicationRecord
  validates :provider, presence: true
  validates :model, presence: true
  validates :tier, presence: true, inclusion: { in: 1..2 }
  validates :total_requests, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :average_rating, numericality: { in: 0..5 }, allow_nil: true

  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :by_tier, ->(tier) { where(tier: tier) }
  scope :top_rated, -> { order(average_rating: :desc) }
  scope :most_used, -> { order(total_requests: :desc) }

  def success_rate
    return 0 if total_requests.zero?
    ((total_requests - negative_feedback_count).to_f / total_requests * 100).round(2)
  end

  def positive_rate
    return 0 if total_requests.zero?
    (positive_feedback_count.to_f / total_requests * 100).round(2)
  end
end
