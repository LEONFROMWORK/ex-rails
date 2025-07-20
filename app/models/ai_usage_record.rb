# frozen_string_literal: true

class AiUsageRecord < ApplicationRecord
  belongs_to :user, optional: true

  validates :model_id, presence: true
  validates :provider, presence: true
  validates :cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :input_tokens, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :output_tokens, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :request_type, presence: true

  enum provider: {
    openai: 0,
    anthropic: 1,
    google: 2,
    openrouter: 3
  }

  enum request_type: {
    chat: 0,
    completion: 1,
    analysis: 2,
    embedding: 3,
    other: 4
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :by_provider, ->(provider) { where(provider: provider) }
  scope :by_model, ->(model_id) { where(model_id: model_id) }
  scope :this_month, -> { where(created_at: Date.current.beginning_of_month..Date.current.end_of_month) }
  scope :today, -> { where(created_at: Date.current.beginning_of_day..Date.current.end_of_day) }

  def self.total_cost_for_period(start_date, end_date)
    by_date_range(start_date, end_date).sum(:cost)
  end

  def self.total_requests_for_period(start_date, end_date)
    by_date_range(start_date, end_date).count
  end

  def self.total_tokens_for_period(start_date, end_date)
    records = by_date_range(start_date, end_date)
    {
      input: records.sum(:input_tokens),
      output: records.sum(:output_tokens),
      total: records.sum(:input_tokens) + records.sum(:output_tokens)
    }
  end

  def self.usage_by_model(start_date, end_date)
    by_date_range(start_date, end_date)
      .group(:model_id)
      .group_by(&:model_id)
      .transform_values do |records|
        {
          cost: records.sum(&:cost),
          requests: records.count,
          input_tokens: records.sum(&:input_tokens),
          output_tokens: records.sum(&:output_tokens)
        }
      end
  end

  def self.usage_by_provider(start_date, end_date)
    by_date_range(start_date, end_date)
      .group(:provider)
      .group_by(&:provider)
      .transform_values do |records|
        {
          cost: records.sum(&:cost),
          requests: records.count,
          input_tokens: records.sum(&:input_tokens),
          output_tokens: records.sum(&:output_tokens)
        }
      end
  end

  def self.daily_usage(start_date, end_date)
    by_date_range(start_date, end_date)
      .group_by { |record| record.created_at.to_date }
      .transform_values do |records|
        {
          cost: records.sum(&:cost),
          requests: records.count,
          input_tokens: records.sum(&:input_tokens),
          output_tokens: records.sum(&:output_tokens)
        }
      end
  end

  def self.create_from_api_call(model_id:, provider:, cost:, input_tokens:, output_tokens:, request_type: :other, user: nil, metadata: {})
    create!(
      model_id: model_id,
      provider: provider,
      cost: cost,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      request_type: request_type,
      user: user,
      metadata: metadata,
      created_at: Time.current
    )
  end

  def total_tokens
    input_tokens + output_tokens
  end

  def cost_per_token
    return 0 if total_tokens.zero?
    cost / total_tokens
  end

  def efficiency_score
    # Calculate efficiency score based on cost per token and response quality
    # This is a simplified version - in practice, you might use more sophisticated metrics
    base_score = case provider
    when "openai"
                   7.0
    when "anthropic"
                   8.0
    when "google"
                   6.0
    else
                   5.0
    end

    # Adjust based on cost efficiency
    if cost_per_token < 0.00001
      base_score + 1.0
    elsif cost_per_token > 0.0001
      base_score - 1.0
    else
      base_score
    end.clamp(0.0, 10.0)
  end

  def self.monthly_spending_limit
    # Get monthly spending limit from configuration
    Rails.application.credentials.dig(:ai, :monthly_limit) ||
    ENV["AI_MONTHLY_LIMIT"]&.to_f ||
    25.0
  end

  def self.current_month_spending
    this_month.sum(:cost)
  end

  def self.remaining_budget
    monthly_spending_limit - current_month_spending
  end

  def self.budget_utilization_percentage
    (current_month_spending / monthly_spending_limit * 100).round(1)
  end
end
