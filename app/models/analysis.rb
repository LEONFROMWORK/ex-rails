# frozen_string_literal: true

class Analysis < ApplicationRecord
  # Associations
  belongs_to :excel_file
  belongs_to :user

  # Enums
  enum :ai_tier_used, { rule_based: 0, tier1: 1, tier2: 2 }
  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  # Validations
  validates :detected_errors, presence: true
  validates :ai_tier_used, presence: true
  validates :credits_used, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :confidence_score, numericality: { in: 0..1 }, allow_nil: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: :completed) }
  scope :by_tier, ->(tier) { where(ai_tier_used: tier) }
  scope :high_confidence, -> { where("confidence_score >= ?", 0.85) }
  scope :with_formulas, -> { where("formula_count > 0") }
  scope :high_formula_complexity, -> { where("formula_complexity_score >= ?", 3.0) }
  scope :with_circular_references, -> { where.not(circular_references: nil) }

  # Callbacks
  before_save :calculate_counts
  after_create :invalidate_analysis_cache
  after_update :invalidate_analysis_cache
  after_destroy :invalidate_analysis_cache

  # Instance methods
  def successful?
    completed? && error_count.positive?
  end

  def fix_rate
    return 0 if error_count.zero?

    ((fixed_count.to_f / error_count) * 100).round(2)
  end

  def tier_name
    case ai_tier_used
    when "tier1" then "Basic AI (GPT-3.5/Haiku)"
    when "tier2" then "Advanced AI (GPT-4/Opus)"
    else "Rule-based"
    end
  end

  def estimated_time_saved
    # Rough estimate: 2 minutes per error fixed manually
    (fixed_count * 2.0).round(1)
  end

  # FormulaEngine 분석 관련 메서드들
  def has_formula_analysis?
    formula_analysis.present?
  end

  def formula_complexity_level
    return "Unknown" unless formula_complexity_score

    case formula_complexity_score
    when 0..1.0 then "Low"
    when 1.1..2.5 then "Medium"
    when 2.6..4.0 then "High"
    else "Very High"
    end
  end

  def most_used_functions
    return [] unless formula_functions.present?

    formula_functions.dig("function_usage")&.sort_by { |func| -func["count"] }&.first(5) || []
  end

  def has_circular_references?
    circular_references.present? && circular_references.any?
  end

  def circular_reference_count
    return 0 unless has_circular_references?

    circular_references.is_a?(Array) ? circular_references.size : 0
  end

  def formula_error_count
    return 0 unless formula_errors.present?

    formula_errors.is_a?(Array) ? formula_errors.size : 0
  end

  def optimization_suggestion_count
    return 0 unless formula_optimization_suggestions.present?

    formula_optimization_suggestions.is_a?(Array) ? formula_optimization_suggestions.size : 0
  end

  private

  def calculate_counts
    if detected_errors.is_a?(Array)
      self.error_count = detected_errors.size
    end

    if corrections.is_a?(Array)
      self.fixed_count = corrections.size
    end
  end

  def invalidate_analysis_cache
    CacheService.instance.invalidate_analysis_cache(id, excel_file_id)
    CacheService.instance.invalidate_user_cache(user_id) if user_id
  end
end
