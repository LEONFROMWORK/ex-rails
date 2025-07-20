# frozen_string_literal: true

class ChatMessage < ApplicationRecord
  belongs_to :chat_conversation
  belongs_to :user
  has_many :ai_feedbacks, dependent: :destroy

  # Validations
  validates :content, presence: true
  validates :role, inclusion: { in: %w[user assistant system] }
  validates :ai_tier_used, inclusion: { in: 1..2 }, allow_nil: true
  validates :confidence_score, numericality: { in: 0..1 }, allow_nil: true
  validates :user_rating, inclusion: { in: 1..5 }, allow_nil: true

  # Scopes
  scope :user_messages, -> { where(role: "user") }
  scope :assistant_messages, -> { where(role: "assistant") }
  scope :recent, -> { order(created_at: :desc) }
  scope :with_feedback, -> { where.not(user_rating: nil) }
  scope :high_confidence, -> { where("confidence_score >= ?", 0.8) }
  scope :by_tier, ->(tier) { where(ai_tier_used: tier) }

  # Callbacks
  after_create :update_conversation_stats

  private

  def update_conversation_stats
    chat_conversation.increment_message_count!
    chat_conversation.add_credits_used!(credits_used) if credits_used > 0
  end
end
