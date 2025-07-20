# frozen_string_literal: true

# 해결되지 않은 문제 보고서 모델
class ProblemReport < ApplicationRecord
  belongs_to :user
  belongs_to :excel_file, optional: true
  has_many :problem_report_responses
  has_many :problem_report_followups

  # 상태
  STATUSES = {
    pending: "대기중",
    assigned: "할당됨",
    in_progress: "처리중",
    resolved: "해결됨",
    closed: "종료됨",
    escalated: "상위 전달됨"
  }.freeze

  # 카테고리
  CATEGORIES = {
    formula_error: "수식 오류",
    pivot_table: "피벗 테이블",
    visualization: "차트/시각화",
    data_io: "데이터 입출력",
    performance: "성능 문제",
    general_error: "일반 오류",
    other: "기타"
  }.freeze

  # 우선순위
  PRIORITIES = {
    critical: "긴급",
    high: "높음",
    medium: "보통",
    low: "낮음"
  }.freeze

  # 긴급도
  URGENCIES = {
    urgent: "긴급",
    high: "높음",
    normal: "보통"
  }.freeze

  # 검증
  validates :query, presence: true
  validates :status, inclusion: { in: STATUSES.keys.map(&:to_s) }
  validates :category, inclusion: { in: CATEGORIES.keys.map(&:to_s) }, allow_nil: true
  validates :priority, inclusion: { in: PRIORITIES.keys.map(&:to_s) }, allow_nil: true
  validates :urgency, inclusion: { in: URGENCIES.keys.map(&:to_s) }, allow_nil: true

  # 스코프
  scope :pending, -> { where(status: "pending") }
  scope :active, -> { where.not(status: [ "resolved", "closed" ]) }
  scope :high_priority, -> { where(priority: [ "critical", "high" ]) }
  scope :recent, -> { order(created_at: :desc) }

  # 콜백
  after_create :increment_user_report_count
  after_update :notify_status_change, if: :saved_change_to_status?

  # 인스턴스 메서드
  def assign_to(expert_user)
    update!(
      status: "assigned",
      assigned_to_id: expert_user.id,
      assigned_at: Time.current
    )

    # 전문가에게 알림
    ProblemReportMailer.assignment_notification(expert_user, self).deliver_later
  end

  def resolve_with(solution)
    transaction do
      update!(
        status: "resolved",
        resolved_at: Time.current,
        resolution: solution
      )

      # 해결책을 KnowledgeItem으로 변환 (선택적)
      if solution[:create_knowledge_item]
        create_knowledge_item_from_solution(solution)
      end

      # 사용자에게 알림
      ProblemReportMailer.resolution_notification(user, self).deliver_later
    end
  end

  def escalate(reason: nil)
    update!(
      status: "escalated",
      escalated_at: Time.current,
      escalation_reason: reason
    )

    # 상위 관리자에게 알림
    notify_escalation
  end

  def add_response(responder:, content:)
    problem_report_responses.create!(
      user: responder,
      content: content,
      created_at: Time.current
    )
  end

  def response_time
    return nil unless resolved_at && reported_at

    TimeDifferenceCalculator.calculate(reported_at, resolved_at)
  end

  def overdue?
    return false if resolved?

    expected_resolution_time = case priority
    when "critical" then 2.hours
    when "high" then 8.hours
    when "medium" then 24.hours
    else 72.hours
    end

    Time.current > reported_at + expected_resolution_time
  end

  def resolved?
    status.in?([ "resolved", "closed" ])
  end

  private

  def increment_user_report_count
    user.increment!(:problem_reports_count)
  end

  def notify_status_change
    return unless user

    ActionCable.server.broadcast(
      "problem_reports_#{user.id}",
      {
        type: "status_update",
        report_id: id,
        new_status: status,
        message: "문제 보고서 ##{id}의 상태가 #{STATUSES[status.to_sym]}(으)로 변경되었습니다."
      }
    )
  end

  def create_knowledge_item_from_solution(solution)
    KnowledgeItem.create!(
      question: query,
      answer: solution[:content],
      excel_functions: solution[:excel_functions] || [],
      code_snippets: solution[:code_snippets] || [],
      tags: solution[:tags] || [],
      difficulty: "medium",
      quality_score: 0.8,
      source: "problem_report_#{id}",
      metadata: {
        problem_report_id: id,
        resolved_by: assigned_to_id,
        category: category
      }
    )
  end

  def notify_escalation
    EscalationNotificationJob.perform_later(self)
  end
end
