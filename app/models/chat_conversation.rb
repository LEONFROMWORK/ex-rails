# frozen_string_literal: true

class ChatConversation < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :excel_file, optional: true
  has_many :messages, class_name: "ChatMessage", dependent: :destroy

  # Enums
  enum :status, { active: 0, archived: 1 }

  # Validations
  validates :message_count, numericality: { greater_than_or_equal_to: 0 }
  validates :total_credits_used, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :recent, -> { order(updated_at: :desc) }
  scope :active, -> { where(status: :active) }
  scope :with_file, -> { where.not(excel_file_id: nil) }

  # Callbacks
  before_create :set_default_title

  # Instance methods
  def increment_message_count!
    increment!(:message_count)
  end

  def add_credits_used!(tokens)
    increment!(:total_credits_used, tokens)
  end

  def average_tokens_per_message
    return 0 if message_count.zero?

    (total_credits_used.to_f / message_count).round(2)
  end

  private

  def set_default_title
    self.title ||= if excel_file.present?
                     "Chat about #{excel_file.original_name}"
    else
                     "New conversation #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    end
  end
end
