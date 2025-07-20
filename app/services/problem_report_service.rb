# frozen_string_literal: true

# 해결되지 않은 문제를 보고하고 처리하는 서비스
class ProblemReportService < ApplicationService
  def initialize(user:, query:, context:, additional_info: {})
    @user = user
    @query = query
    @context = context
    @additional_info = additional_info
  end

  def call
    ActiveRecord::Base.transaction do
      # 1. 문제 보고서 생성
      report = create_problem_report

      # 2. 자동 분류 및 우선순위 설정
      classify_and_prioritize(report)

      # 3. 관련 팀/전문가에게 알림
      notify_relevant_parties(report)

      # 4. 임시 해결책 제공
      temporary_solution = provide_temporary_solution(report)

      # 5. 팔로우업 스케줄링
      schedule_followup(report)

      Result.success({
        report_id: report.id,
        status: report.status,
        estimated_response_time: estimate_response_time(report),
        temporary_solution: temporary_solution,
        tracking_url: "/problems/#{report.id}"
      })
    end
  rescue StandardError => e
    Rails.logger.error("문제 보고 실패: #{e.message}")
    Result.failure("문제 보고 중 오류가 발생했습니다: #{e.message}")
  end

  private

  def create_problem_report
    ProblemReport.create!(
      user: @user,
      query: @query,
      context: @context,
      additional_info: @additional_info,
      status: "pending",
      reported_at: Time.current,
      excel_file_id: @additional_info[:excel_file_id],
      error_details: @additional_info[:error_details]
    )
  end

  def classify_and_prioritize(report)
    # 문제 분류
    category = classify_problem(report.query)

    # 우선순위 계산
    priority = calculate_priority(report)

    # 긴급도 평가
    urgency = evaluate_urgency(report)

    report.update!(
      category: category,
      priority: priority,
      urgency: urgency,
      classified_at: Time.current
    )
  end

  def classify_problem(query)
    # 키워드 기반 분류 (실제로는 ML 모델 사용 가능)
    case query.downcase
    when /formula|수식|function|함수/
      "formula_error"
    when /pivot|피벗/
      "pivot_table"
    when /chart|차트|graph/
      "visualization"
    when /import|가져오기|export|내보내기/
      "data_io"
    when /performance|성능|slow|느림/
      "performance"
    when /error|오류|에러/
      "general_error"
    else
      "other"
    end
  end

  def calculate_priority(report)
    score = 0

    # 사용자 등급에 따른 가중치
    score += case @user.subscription_level
    when "enterprise" then 30
    when "pro" then 20
    when "basic" then 10
    else 5
    end

    # 문제 카테고리별 가중치
    score += case report.category
    when "formula_error" then 15
    when "performance" then 20
    when "data_io" then 10
    else 5
    end

    # 영향 범위
    if @additional_info[:affected_users_count].to_i > 10
      score += 20
    elsif @additional_info[:affected_users_count].to_i > 1
      score += 10
    end

    # 우선순위 레벨 결정
    case score
    when 60..100 then "critical"
    when 40..59 then "high"
    when 20..39 then "medium"
    else "low"
    end
  end

  def evaluate_urgency(report)
    # 긴급도 평가 로직
    urgent_keywords = %w[urgent 긴급 asap 급함 critical deadline]

    if urgent_keywords.any? { |keyword| report.query.downcase.include?(keyword) }
      "urgent"
    elsif report.priority == "critical"
      "high"
    else
      "normal"
    end
  end

  def notify_relevant_parties(report)
    # 카테고리별 담당자 알림
    recipients = case report.category
    when "formula_error"
                   User.where(role: "formula_expert")
    when "performance"
                   User.where(role: "performance_engineer")
    else
                   User.where(role: "support_staff")
    end

    recipients.each do |recipient|
      ProblemReportMailer.new_report_notification(recipient, report).deliver_later
    end

    # Slack 알림 (긴급한 경우)
    if report.priority == "critical" || report.urgency == "urgent"
      SlackNotificationService.notify_urgent_problem(report)
    end
  end

  def provide_temporary_solution(report)
    solutions = []

    # 카테고리별 임시 해결책
    case report.category
    when "formula_error"
      solutions << {
        title: "일반적인 수식 오류 해결 방법",
        steps: [
          "수식의 괄호가 올바르게 닫혀있는지 확인하세요",
          "참조하는 셀이 올바른지 확인하세요",
          "#REF!, #VALUE! 등의 오류 메시지를 확인하세요",
          "수식을 단계별로 분해하여 문제를 찾아보세요"
        ],
        resources: [
          { title: "Excel 수식 오류 가이드", url: "/guides/formula-errors" }
        ]
      }
    when "performance"
      solutions << {
        title: "성능 개선 방법",
        steps: [
          "불필요한 수식을 값으로 변환하세요",
          "조건부 서식을 최소화하세요",
          "휘발성 함수(NOW, RAND 등) 사용을 줄이세요",
          "외부 링크를 제거하거나 최소화하세요"
        ],
        resources: [
          { title: "Excel 성능 최적화 가이드", url: "/guides/performance" }
        ]
      }
    end

    # 일반적인 해결책
    solutions << {
      title: "추가 지원",
      steps: [
        "문제가 지속되면 파일을 저장하고 Excel을 재시작하세요",
        "최신 버전으로 Excel을 업데이트하세요",
        "안전 모드에서 Excel을 실행해보세요"
      ],
      resources: [
        { title: "커뮤니티 포럼", url: "/community" },
        { title: "실시간 채팅 지원", url: "/support/chat" }
      ]
    }

    solutions
  end

  def schedule_followup(report)
    # 우선순위에 따른 팔로우업 스케줄
    delay = case report.priority
    when "critical" then 2.hours
    when "high" then 1.day
    when "medium" then 3.days
    else 1.week
    end

    ProblemReportFollowupJob.set(wait: delay).perform_later(report.id)
  end

  def estimate_response_time(report)
    base_time = case report.priority
    when "critical" then 2
    when "high" then 8
    when "medium" then 24
    else 72
    end

    # 업무 시간 고려
    if Time.current.on_weekend?
      base_time += 48
    elsif Time.current.hour < 9 || Time.current.hour > 18
      base_time += 12
    end

    "#{base_time}시간 이내"
  end
end
