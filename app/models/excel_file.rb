# frozen_string_literal: true

class ExcelFile < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :analyses, dependent: :destroy
  has_many :chat_conversations, dependent: :nullify

  # Enums
  enum :status, { uploaded: 0, processing: 1, analyzed: 2, failed: 3, cancelled: 4 }

  # Validations
  validates :original_name, presence: true
  validates :file_path, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :analyzed, -> { where(status: :analyzed) }
  scope :processing_or_analyzed, -> { where(status: [ :processing, :analyzed ]) }

  # Instance methods
  def latest_analysis
    analyses.order(created_at: :desc).first
  end

  def has_analysis?
    analyses.exists?
  end

  def total_errors
    latest_analysis&.error_count || 0
  end

  def total_fixed
    latest_analysis&.fixed_count || 0
  end

  def file_extension
    File.extname(original_name).downcase
  end

  def human_file_size
    if file_size < 1024
      "#{file_size} B"
    elsif file_size < 1024 * 1024
      "#{(file_size / 1024.0).round(2)} KB"
    elsif file_size < 1024 * 1024 * 1024
      "#{(file_size / (1024.0 * 1024)).round(2)} MB"
    else
      "#{(file_size / (1024.0 * 1024 * 1024)).round(2)} GB"
    end
  end

  def processing_time
    return nil unless analyzed? && analyses.any?

    latest = latest_analysis
    return nil unless latest

    (latest.created_at - created_at).round(2)
  end

  def can_be_analyzed?
    uploaded? || failed?
  end

  def can_be_cancelled?
    uploaded? || processing?
  end

  def analysis_progress
    case status
    when "uploaded"
      10
    when "processing"
      50
    when "analyzed"
      100
    when "failed", "cancelled"
      0
    else
      0
    end
  end

  def file_exists?
    File.exist?(file_path)
  end

  def cleanup_file!
    return unless file_exists?

    begin
      File.delete(file_path)
      Rails.logger.info("Deleted file: #{file_path}")
    rescue StandardError => e
      Rails.logger.error("Failed to delete file #{file_path}: #{e.message}")
    end
  end
end
