# Knowledge base thread model for Reddit and Stack Overflow Q&A data
class KnowledgeThread < ApplicationRecord
  # Enums
  enum source: {
    manual: "manual",
    reddit: "reddit",
    stackoverflow: "stackoverflow"
  }

  enum category: {
    general: "general",
    formula_errors: "formula_errors",
    formula_functions: "formula_functions",
    pivot_tables: "pivot_tables",
    vba_macros: "vba_macros",
    data_analysis: "data_analysis",
    charts: "charts",
    formatting: "formatting"
  }

  # Validations
  validates :external_id, presence: true
  validates :source, presence: true
  validates :title, presence: true, length: { minimum: 5, maximum: 500 }
  validates :quality_score, presence: true,
            numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 10.0 }
  validates :external_id, uniqueness: { scope: :source }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :by_source, ->(source) { where(source: source) }
  scope :by_category, ->(category) { where(category: category) }
  scope :high_quality, -> { where("quality_score >= ?", 7.0) }
  scope :op_confirmed_reddit, -> { reddit.where(op_confirmed: true) }
  scope :recent, -> { order(processed_at: :desc, created_at: :desc) }
  scope :by_quality, -> { order(quality_score: :desc) }

  # Class methods
  def self.reddit_stats
    reddit_threads = reddit.active

    {
      total_threads: reddit_threads.count,
      op_confirmed_count: reddit_threads.where(op_confirmed: true).count,
      average_quality: reddit_threads.average(:quality_score)&.round(1) || 0.0,
      categories: reddit_threads.group(:category).count,
      quality_tiers: {
        "excellent" => reddit_threads.where("quality_score >= ?", 9.0).count,
        "good" => reddit_threads.where("quality_score >= ? AND quality_score < ?", 7.5, 9.0).count,
        "fair" => reddit_threads.where("quality_score >= ? AND quality_score < ?", 6.5, 7.5).count,
        "poor" => reddit_threads.where("quality_score < ?", 6.5).count
      },
      last_sync: reddit_threads.maximum(:processed_at) || 1.week.ago
    }
  end

  def self.stackoverflow_stats
    so_threads = stackoverflow.active

    {
      total_threads: so_threads.count,
      accepted_answers: so_threads.where("source_metadata->>'isAccepted' = 'true'").count,
      average_quality: so_threads.average(:quality_score)&.round(1) || 0.0,
      categories: so_threads.group(:category).count,
      last_sync: so_threads.maximum(:processed_at) || 1.week.ago
    }
  end

  def self.overall_stats
    {
      total_documents: active.count,
      sources: active.group(:source).count,
      categories: active.group(:category).count,
      source_quality: active.group(:source).average(:quality_score).transform_values { |v| v&.round(1) || 0.0 },
      last_updated: maximum(:processed_at) || 1.week.ago
    }
  end

  # Instance methods
  def reddit?
    source == "reddit"
  end

  def stackoverflow?
    source == "stackoverflow"
  end

  def high_quality?
    quality_score >= 7.0
  end

  def display_source
    case source
    when "reddit" then "Reddit r/excel"
    when "stackoverflow" then "Stack Overflow"
    when "manual" then "수동 입력"
    else source.humanize
    end
  end

  def category_display_name
    case category
    when "formula_errors" then "함수 오류"
    when "formula_functions" then "함수 사용법"
    when "pivot_tables" then "피벗 테이블"
    when "vba_macros" then "VBA 매크로"
    when "data_analysis" then "데이터 분석"
    when "charts" then "차트"
    when "formatting" then "서식"
    when "general" then "일반"
    else category.humanize
    end
  end

  def quality_tier
    case quality_score
    when 9.0..10.0 then "excellent"
    when 7.5...9.0 then "good"
    when 6.5...7.5 then "fair"
    else "poor"
    end
  end

  def quality_tier_display
    case quality_tier
    when "excellent" then "우수"
    when "good" then "양호"
    when "fair" then "보통"
    when "poor" then "미흡"
    end
  end

  # For Reddit threads
  def reddit_op_confirmed?
    reddit? && op_confirmed?
  end

  # For Stack Overflow threads
  def stackoverflow_accepted?
    stackoverflow? && source_metadata&.dig("isAccepted") == true
  end

  def platform_metadata
    return {} unless source_metadata

    case source
    when "reddit"
      {
        submission_id: source_metadata["submission_id"],
        solution_comment_id: source_metadata["solution_comment_id"],
        op_confirmed: source_metadata["op_confirmed"],
        solution_type: source_metadata["solution_type"],
        flair: source_metadata["flair"]
      }
    when "stackoverflow"
      {
        question_id: source_metadata["question_id"],
        answer_id: source_metadata["answer_id"],
        is_accepted: source_metadata["isAccepted"],
        view_count: source_metadata["view_count"],
        tags: source_metadata["tags"]
      }
    else
      source_metadata
    end
  end

  def to_rag_format
    # 레거시 형식 - 하위 호환성 유지
    {
      id: id,
      title: title,
      category: category,
      quality: quality_score,
      source: source,
      source_metadata: {
        platform: source,
        votes: votes,
        is_accepted: stackoverflow_accepted?,
        op_confirmed: reddit_op_confirmed?,
        thread_url: source_url
      },
      content: {
        question: question_content,
        answer: answer_content
      }
    }
  end

  def to_trd_format
    # BigData TRD 표준 형식으로 변환 (권장 형식)
    {
      id: "rails_#{source}_#{external_id}",
      question: title.present? ? "#{title}: #{question_content}" : question_content,
      answer: answer_content,
      qualityScore: {
        total: (quality_score * 10).round, # 0-100 스케일로 변환
        breakdown: {
          relevance: ((quality_score * 10) * 0.4).round,
          clarity: ((quality_score * 10) * 0.3).round,
          completeness: ((quality_score * 10) * 0.3).round
        }
      },
      source: source,
      metadata: {
        category: category,
        difficulty: determine_difficulty,
        tags: extract_tags,
        platform: source,
        votes: votes,
        opConfirmed: reddit_op_confirmed?,
        isAccepted: stackoverflow_accepted?,
        threadUrl: source_url,
        processedAt: processed_at&.iso8601 || created_at.iso8601,
        railsId: id,
        externalId: external_id,
        sourceMetadata: source_metadata
      }
    }
  end

  private

  def determine_difficulty
    case quality_score
    when 0.0..4.0 then "beginner"
    when 4.0..7.0 then "intermediate"
    when 7.0..10.0 then "advanced"
    else "intermediate"
    end
  end

  def extract_tags
    tags = []
    tags << source
    tags << category if category.present?
    tags << "op_confirmed" if reddit_op_confirmed?
    tags << "accepted_answer" if stackoverflow_accepted?
    tags << quality_tier
    tags.compact.uniq
  end
end
