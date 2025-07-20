# frozen_string_literal: true

module Api
  module V1
    # API 컨트롤러 - Knowledge Threads 데이터 익스포트
    class KnowledgeThreadsController < Api::V1::BaseController
  before_action :require_api_key

  # GET /api/v1/knowledge_threads
  # 지식 베이스 스레드 목록 조회 (페이지네이션 지원)
  def index
    @threads = KnowledgeThread.active
                              .includes(:source_metadata)
                              .page(params[:page] || 1)
                              .per(params[:per_page] || 100)

    # 필터링 옵션들
    @threads = @threads.by_source(params[:source]) if params[:source].present?
    @threads = @threads.by_category(params[:category]) if params[:category].present?
    @threads = @threads.where("quality_score >= ?", params[:min_quality]) if params[:min_quality].present?
    @threads = @threads.where("updated_at >= ?", params[:since]) if params[:since].present?

    render json: {
      threads: @threads.map(&:to_rag_format),
      pagination: {
        current_page: @threads.current_page,
        total_pages: @threads.total_pages,
        total_count: @threads.total_count,
        per_page: @threads.limit_value
      },
      meta: {
        source_counts: KnowledgeThread.active.group(:source).count,
        category_counts: KnowledgeThread.active.group(:category).count,
        quality_stats: {
          average: KnowledgeThread.active.average(:quality_score)&.round(2) || 0.0,
          min: KnowledgeThread.active.minimum(:quality_score) || 0.0,
          max: KnowledgeThread.active.maximum(:quality_score) || 0.0
        },
        last_updated: KnowledgeThread.active.maximum(:updated_at)
      }
    }
  end

  # GET /api/v1/knowledge_threads/:id
  # 특정 스레드 상세 조회
  def show
    @thread = KnowledgeThread.active.find_by!(
      external_id: params[:id],
      source: params[:source] || "reddit"
    )

    render json: {
      thread: @thread.to_rag_format,
      meta: {
        raw_metadata: @thread.source_metadata,
        platform_data: @thread.platform_metadata,
        quality_tier: @thread.quality_tier,
        display_source: @thread.display_source
      }
    }
  end

  # GET /api/v1/knowledge_threads/export
  # 전체 데이터 익스포트 (JSON Lines 형식)
  def export
    export_format = params[:format] || "json"
    batch_size = [ params[:batch_size]&.to_i || 1000, 5000 ].min

    case export_format
    when "jsonl"
      export_jsonl(batch_size)
    when "json"
      export_json(batch_size)
    else
      render json: { error: "Unsupported export format" }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/knowledge_threads/stats
  # 통계 정보
  def stats
    render json: {
      overall_stats: KnowledgeThread.overall_stats,
      reddit_stats: KnowledgeThread.reddit_stats,
      stackoverflow_stats: KnowledgeThread.stackoverflow_stats,
      quality_distribution: quality_distribution_stats,
      category_distribution: category_distribution_stats,
      recent_activity: recent_activity_stats
    }
  end

  private

  def require_api_key
    api_key = request.headers["Authorization"]&.gsub(/^Bearer /, "") || params[:api_key]

    unless api_key == Rails.application.credentials.api_key ||
           api_key == ENV["EXCELAPP_API_KEY"]
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def export_jsonl(batch_size)
    response.headers["Content-Type"] = "application/x-ndjson"
    response.headers["Content-Disposition"] =
      "attachment; filename=\"knowledge_threads_#{Date.current}.jsonl\""

    # 스트리밍 응답으로 메모리 효율적으로 처리
    self.response_body = Enumerator.new do |yielder|
      KnowledgeThread.active.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |thread|
          yielder << "#{thread.to_rag_format.to_json}\n"
        end
      end
    end
  end

  def export_json(batch_size)
    threads = KnowledgeThread.active.limit(batch_size)

    # 필터링 적용
    threads = threads.by_source(params[:source]) if params[:source].present?
    threads = threads.by_category(params[:category]) if params[:category].present?
    threads = threads.where("quality_score >= ?", params[:min_quality]) if params[:min_quality].present?

    render json: {
      threads: threads.map(&:to_rag_format),
      exported_at: Time.current.iso8601,
      total_count: threads.count,
      filters_applied: {
        source: params[:source],
        category: params[:category],
        min_quality: params[:min_quality]
      }.compact
    }
  end

  def quality_distribution_stats
    KnowledgeThread.active.group(
      "CASE
        WHEN quality_score >= 9.0 THEN 'excellent'
        WHEN quality_score >= 7.5 THEN 'good'
        WHEN quality_score >= 6.0 THEN 'fair'
        ELSE 'poor'
      END"
    ).count
  end

  def category_distribution_stats
    KnowledgeThread.active.group(:category).count
  end

  def recent_activity_stats
    {
      last_24h: KnowledgeThread.active.where("created_at > ?", 24.hours.ago).count,
      last_week: KnowledgeThread.active.where("created_at > ?", 1.week.ago).count,
      last_month: KnowledgeThread.active.where("created_at > ?", 1.month.ago).count,
      recent_by_source: KnowledgeThread.active
                          .where("created_at > ?", 1.week.ago)
                          .group(:source)
                          .count
    }
  end
    end
  end
end
