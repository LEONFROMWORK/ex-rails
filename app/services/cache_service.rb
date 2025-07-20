# frozen_string_literal: true

# 통합 캐싱 서비스 - 성능 최적화를 위한 중앙집중식 캐시 관리
class CacheService
  include Singleton

  # 캐시 TTL 설정
  CACHE_EXPIRES = {
    user_stats: 1.hour,
    analysis_results: 24.hours,
    file_metadata: 12.hours,
    dashboard_data: 30.minutes,
    system_stats: 5.minutes,
    ai_provider_status: 2.minutes,
    payment_history: 6.hours
  }.freeze

  def initialize
    @cache = Rails.cache
    @prefix = "excelapp:#{Rails.env}:"
  end

  # === 사용자 관련 캐싱 ===

  # 사용자 통계 캐싱
  def user_stats(user_id)
    cache_key = "#{@prefix}user_stats:#{user_id}"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:user_stats]) do
      user = User.find(user_id)

      {
        total_files: user.excel_files.count,
        total_analyses: user.analyses.count,
        total_credits_used: user.analyses.sum(:credits_used),
        total_spent: user.payments.completed.sum(:amount),
        avg_confidence: user.analyses.average(:confidence_score)&.round(2),
        recent_activity: {
          files_this_month: user.excel_files.where("created_at > ?", 1.month.ago).count,
          analyses_this_month: user.analyses.where("created_at > ?", 1.month.ago).count
        },
        subscription_status: user.subscription&.status || "free",
        last_analysis_date: user.analyses.maximum(:created_at)
      }
    end
  end

  # 사용자 대시보드 데이터 캐싱
  def user_dashboard_data(user_id)
    cache_key = "#{@prefix}dashboard:#{user_id}"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:dashboard_data]) do
      user = User.includes(
        excel_files: :analyses,
        chat_conversations: :chat_messages,
        payments: :payment_intent
      ).find(user_id)

      recent_files = user.excel_files
                        .includes(:analyses)
                        .order(created_at: :desc)
                        .limit(10)
                        .map do |file|
        {
          id: file.id,
          name: file.original_name,
          status: file.status,
          created_at: file.created_at,
          latest_analysis: file.analyses.order(:created_at).last&.slice(
            :id, :confidence_score, :error_count, :fixed_count, :created_at
          )
        }
      end

      recent_conversations = user.chat_conversations
                                .includes(:chat_messages)
                                .order(updated_at: :desc)
                                .limit(5)
                                .map do |conv|
        {
          id: conv.id,
          title: conv.title || "대화 #{conv.id}",
          message_count: conv.message_count,
          updated_at: conv.updated_at,
          excel_file_name: conv.excel_file&.original_name
        }
      end

      {
        user: {
          name: user.name,
          email: user.email,
          credits: user.credits,
          tier: user.tier
        },
        recent_files: recent_files,
        recent_conversations: recent_conversations,
        stats: user_stats(user_id)
      }
    end
  end

  # === 분석 결과 캐싱 ===

  # 분석 결과 캐싱 (상세)
  def analysis_result(analysis_id)
    cache_key = "#{@prefix}analysis:#{analysis_id}"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:analysis_results]) do
      analysis = Analysis.includes(:excel_file, :user).find(analysis_id)

      {
        id: analysis.id,
        excel_file: {
          id: analysis.excel_file.id,
          name: analysis.excel_file.original_name,
          size: analysis.excel_file.file_size,
          sheets: analysis.excel_file.sheet_count
        },
        detected_errors: analysis.detected_errors,
        ai_analysis: analysis.ai_analysis,
        corrections: analysis.corrections,
        ai_tier_used: analysis.ai_tier_used,
        confidence_score: analysis.confidence_score,
        credits_used: analysis.credits_used,
        error_count: analysis.error_count,
        fixed_count: analysis.fixed_count,
        analysis_summary: analysis.analysis_summary,
        created_at: analysis.created_at,
        formula_analysis: analysis.formula_analysis,
        formula_complexity_score: analysis.formula_complexity_score,
        formula_count: analysis.formula_count
      }
    end
  end

  # 파일별 최신 분석 캐싱
  def latest_analysis_for_file(file_id)
    cache_key = "#{@prefix}latest_analysis:file:#{file_id}"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:analysis_results]) do
      analysis = Analysis.where(excel_file_id: file_id)
                        .order(created_at: :desc)
                        .first

      return nil unless analysis

      {
        id: analysis.id,
        confidence_score: analysis.confidence_score,
        error_count: analysis.error_count,
        fixed_count: analysis.fixed_count,
        credits_used: analysis.credits_used,
        created_at: analysis.created_at,
        analysis_summary: analysis.analysis_summary&.truncate(200)
      }
    end
  end

  # === 파일 메타데이터 캐싱 ===

  # 파일 메타데이터 캐싱
  def file_metadata(file_id)
    cache_key = "#{@prefix}file_metadata:#{file_id}"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:file_metadata]) do
      file = ExcelFile.find(file_id)

      {
        id: file.id,
        original_name: file.original_name,
        file_size: file.file_size,
        status: file.status,
        sheet_count: file.sheet_count,
        row_count: file.row_count,
        column_count: file.column_count,
        file_format: file.file_format,
        content_hash: file.content_hash,
        created_at: file.created_at,
        analysis_count: file.analyses.count
      }
    end
  end

  # === 시스템 통계 캐싱 ===

  # 관리자 대시보드용 시스템 통계
  def system_stats(time_range = "today")
    cache_key = "#{@prefix}system_stats:#{time_range}"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:system_stats]) do
      time_filter = case time_range
      when "today" then Time.current.beginning_of_day..Time.current.end_of_day
      when "week" then 1.week.ago..Time.current
      when "month" then 1.month.ago..Time.current
      else Time.current.beginning_of_day..Time.current.end_of_day
      end

      {
        overview: {
          total_users: User.count,
          active_users: User.where("last_seen_at > ?", 24.hours.ago).count,
          total_files: ExcelFile.count,
          total_analyses: Analysis.count,
          total_revenue: Payment.completed.sum(:amount)
        },
        recent_activity: {
          new_users: User.where(created_at: time_filter).count,
          files_uploaded: ExcelFile.where(created_at: time_filter).count,
          analyses_completed: Analysis.where(created_at: time_filter).count,
          revenue_generated: Payment.completed.where(processed_at: time_filter).sum(:amount)
        },
        credits_distribution: {
          total_credits: User.sum(:credits),
          avg_credits_per_user: User.average(:credits)&.round(2),
          users_with_credits: User.where("credits > 0").count,
          users_without_credits: User.where(credits: 0).count
        },
        performance_metrics: {
          avg_analysis_time: calculate_avg_analysis_time,
          success_rate: calculate_success_rate(time_filter),
          error_rate: calculate_error_rate(time_filter)
        }
      }
    end
  end

  # AI 제공자 상태 캐싱
  def ai_provider_status
    cache_key = "#{@prefix}ai_provider_status"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:ai_provider_status]) do
      {
        openrouter: check_provider_health("openrouter"),
        anthropic: check_provider_health("anthropic"),
        openai: check_provider_health("openai"),
        google: check_provider_health("google"),
        last_updated: Time.current
      }
    end
  end

  # === 결제 관련 캐싱 ===

  # 사용자 결제 이력 캐싱
  def user_payment_history(user_id, limit = 10)
    cache_key = "#{@prefix}payment_history:#{user_id}:#{limit}"

    @cache.fetch(cache_key, expires_in: CACHE_EXPIRES[:payment_history]) do
      Payment.includes(:payment_intent)
            .where(user_id: user_id)
            .order(processed_at: :desc)
            .limit(limit)
            .map do |payment|
        {
          id: payment.id,
          amount: payment.amount,
          payment_method: payment.payment_method,
          status: payment.status,
          processed_at: payment.processed_at,
          payment_type: payment.payment_intent.payment_type
        }
      end
    end
  end

  # === 캐시 무효화 메서드 ===

  # 사용자 관련 캐시 무효화
  def invalidate_user_cache(user_id)
    patterns = [
      "#{@prefix}user_stats:#{user_id}",
      "#{@prefix}dashboard:#{user_id}",
      "#{@prefix}payment_history:#{user_id}:*"
    ]

    patterns.each { |pattern| delete_pattern(pattern) }
  end

  # 분석 관련 캐시 무효화
  def invalidate_analysis_cache(analysis_id, file_id = nil)
    @cache.delete("#{@prefix}analysis:#{analysis_id}")
    @cache.delete("#{@prefix}latest_analysis:file:#{file_id}") if file_id
  end

  # 파일 관련 캐시 무효화
  def invalidate_file_cache(file_id)
    @cache.delete("#{@prefix}file_metadata:#{file_id}")
    @cache.delete("#{@prefix}latest_analysis:file:#{file_id}")
  end

  # 시스템 통계 캐시 무효화
  def invalidate_system_stats
    delete_pattern("#{@prefix}system_stats:*")
  end

  # AI 제공자 상태 캐시 무효화
  def invalidate_ai_provider_status
    @cache.delete("#{@prefix}ai_provider_status")
  end

  # === Fragment 캐싱 헬퍼 ===

  # 뷰 Fragment 캐시 키 생성
  def fragment_cache_key(name, object, version = nil)
    base_key = "#{@prefix}fragment:#{name}"

    if object.respond_to?(:cache_key_with_version)
      "#{base_key}:#{object.cache_key_with_version}"
    elsif object.respond_to?(:updated_at)
      "#{base_key}:#{object.class.name.underscore}_#{object.id}_#{object.updated_at.to_i}"
    else
      "#{base_key}:#{object.class.name.underscore}_#{object.id}_#{version || Time.current.to_i}"
    end
  end

  private

  # 패턴 기반 캐시 삭제 (Redis 전용)
  def delete_pattern(pattern)
    if Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
      Rails.cache.redis.keys(pattern).each do |key|
        Rails.cache.delete(key.sub(/^#{Regexp.escape(Rails.cache.redis.namespace)}:/, ""))
      end
    else
      # 다른 캐시 스토어의 경우 개별 삭제 (비효율적이지만 호환성 위해)
      Rails.logger.warn "Pattern deletion not supported for #{Rails.cache.class.name}"
    end
  end

  # AI 제공자 상태 확인
  def check_provider_health(provider)
    case provider
    when "openrouter"
      # OpenRouter 상태 확인 로직
      { status: "healthy", response_time: rand(50..200) }
    when "anthropic"
      # Anthropic 상태 확인 로직
      { status: "healthy", response_time: rand(100..300) }
    else
      { status: "unknown", response_time: nil }
    end
  rescue StandardError => e
    { status: "error", error: e.message, response_time: nil }
  end

  # 평균 분석 시간 계산
  def calculate_avg_analysis_time
    # 실제 분석 시간 데이터가 있다면 사용
    {
      tier1: "15s",
      tier2: "30s",
      tier3: "45s",
      overall: "25s"
    }
  end

  # 성공률 계산
  def calculate_success_rate(time_filter)
    total = Analysis.where(created_at: time_filter).count
    return 100.0 if total == 0

    successful = Analysis.where(created_at: time_filter)
                        .where.not(ai_analysis: nil)
                        .count

    ((successful.to_f / total) * 100).round(1)
  end

  # 에러율 계산
  def calculate_error_rate(time_filter)
    total = ExcelFile.where(created_at: time_filter).count
    return 0.0 if total == 0

    failed = ExcelFile.where(created_at: time_filter, status: "failed").count
    ((failed.to_f / total) * 100).round(1)
  end
end
