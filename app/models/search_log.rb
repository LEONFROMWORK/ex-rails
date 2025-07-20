# frozen_string_literal: true

# 검색 로그 및 분석을 위한 모델
class SearchLog < ApplicationRecord
  belongs_to :user, optional: true

  # pgvector를 사용한 쿼리 임베딩
  has_neighbors :query_embedding

  # 이벤트 타입
  EVENT_TYPES = {
    knowledge_base_hit: "지식베이스 검색 성공",
    knowledge_base_miss: "지식베이스 검색 실패",
    ai_fallback_used: "AI 폴백 사용",
    problem_reported: "문제 보고됨",
    solution_rated: "해결책 평가됨"
  }.freeze

  # 검증
  validates :query, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES.keys.map(&:to_s) }

  # 스코프
  scope :recent, -> { where("created_at > ?", 30.days.ago) }
  scope :successful, -> { where(event_type: "knowledge_base_hit") }
  scope :failed, -> { where(event_type: "knowledge_base_miss") }

  # 통계 메서드
  def self.success_rate(period = 30.days)
    total = where("created_at > ?", period.ago).count
    return 0 if total.zero?

    successful_count = where("created_at > ?", period.ago)
                      .where(event_type: "knowledge_base_hit")
                      .count

    (successful_count.to_f / total * 100).round(2)
  end

  def self.popular_failed_queries(limit = 10)
    failed
      .group(:query)
      .order("COUNT(*) DESC")
      .limit(limit)
      .pluck(:query, "COUNT(*)")
  end

  def self.trending_queries(period = 7.days, limit = 20)
    where("created_at > ?", period.ago)
      .group(:query)
      .order("COUNT(*) DESC")
      .limit(limit)
      .pluck(:query, "COUNT(*)")
  end
end
