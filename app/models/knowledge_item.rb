class KnowledgeItem < ApplicationRecord
  # 검증
  validates :question, presence: true, length: { minimum: 10 }
  validates :answer, presence: true, length: { minimum: 20 }
  validates :quality_score, presence: true, inclusion: { in: 0.0..10.0 }
  validates :source, presence: true
  validates :difficulty, inclusion: { in: 0..3 }

  # Enum 대신 상수로 난이도 관리
  DIFFICULTIES = {
    easy: 0,
    medium: 1,
    hard: 2,
    expert: 3
  }.freeze

  DIFFICULTY_NAMES = DIFFICULTIES.invert.freeze

  # 스코프
  scope :active, -> { where(is_active: true) }
  scope :by_difficulty, ->(level) { where(difficulty: DIFFICULTIES[level.to_sym]) }
  scope :by_source, ->(source) { where(source: source) }
  scope :high_quality, -> { where("quality_score >= ?", 7.0) }
  scope :recent, -> { order(created_at: :desc) }
  scope :most_used, -> { order(use_count: :desc) }
  scope :most_helpful, -> { order(helpful_votes: :desc) }

  # 인스턴스 메서드
  def difficulty_name
    DIFFICULTY_NAMES[difficulty]
  end

  def difficulty_name=(name)
    self.difficulty = DIFFICULTIES[name.to_sym] if DIFFICULTIES.key?(name.to_sym)
  end

  def increment_search_count!
    increment!(:search_count)
    touch(:last_used)
  end

  def increment_use_count!
    increment!(:use_count)
    touch(:last_used)
  end

  def increment_helpful_votes!
    increment!(:helpful_votes)
  end

  # 벡터 유사성 검색을 위한 클래스 메서드
  def self.vector_search(embedding, limit: 10, threshold: 0.7)
    return none if embedding.blank?

    # pgvector 코사인 유사도 검색
    select("*, 1 - (embedding <=> '[#{embedding.join(',')}]') as similarity")
      .where("1 - (embedding <=> '[#{embedding.join(',')}]') > ?", threshold)
      .where(is_active: true)
      .order("embedding <=> '[#{embedding.join(',')}]'")
      .limit(limit)
  end

  # 중복 확인
  def self.find_duplicate(question, source)
    where(question: question, source: source).first
  end

  # 통계 메서드
  def self.stats_by_source
    group(:source).count
  end

  def self.average_quality_score
    average(:quality_score)
  end

  def self.total_searches
    sum(:search_count)
  end

  def self.total_usage
    sum(:use_count)
  end
end
