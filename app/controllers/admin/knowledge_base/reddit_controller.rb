# Reddit 데이터 관리 컨트롤러
class Admin::KnowledgeBase::RedditController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!

  def index
    @reddit_stats = calculate_reddit_stats
    @recent_threads = fetch_recent_reddit_threads
  end

  def sync_data
    # bigdata 시스템의 Reddit 데이터 동기화
    begin
      sync_result = RedditDataSyncService.perform_sync

      if sync_result.success?
        flash[:notice] = "Reddit 데이터 동기화가 완료되었습니다. #{sync_result.processed_count}개의 스레드를 처리했습니다."
      else
        flash[:alert] = "동기화 중 오류가 발생했습니다: #{sync_result.error_message}"
      end
    rescue => e
      Rails.logger.error "Reddit 데이터 동기화 실패: #{e.message}"
      flash[:alert] = "동기화에 실패했습니다. 관리자에게 문의하세요."
    end

    redirect_to admin_knowledge_base_reddit_index_path
  end

  def thread_analysis
    # 최근 분석 작업들을 조회 (Solid Queue 작업)
    @analysis_jobs = SolidQueue::Job.where(class_name: "RedditAnalysisJob")
                                    .where("created_at > ?", 1.week.ago)
                                    .order(created_at: :desc)
                                    .limit(20)
    @quality_distribution = calculate_quality_distribution
  end

  def bulk_import
    # bigdata 시스템에서 생성된 JSONL 파일 일괄 가져오기
    if params[:file].present?
      begin
        import_result = RedditBulkImportService.import_from_file(params[:file])

        if import_result.success?
          flash[:notice] = "#{import_result.imported_count}개의 Reddit Q&A가 성공적으로 가져와졌습니다."
        else
          flash[:alert] = "가져오기 실패: #{import_result.errors.join(', ')}"
        end
      rescue => e
        Rails.logger.error "Reddit 일괄 가져오기 실패: #{e.message}"
        flash[:alert] = "파일 처리 중 오류가 발생했습니다."
      end
    else
      flash[:alert] = "파일을 선택해주세요."
    end

    redirect_to admin_knowledge_base_reddit_index_path
  end

  private

  def calculate_reddit_stats
    # Use actual model data if available, fallback to mock data
    if KnowledgeThread.reddit.exists?
      KnowledgeThread.reddit_stats
    else
      # Mock data for development/testing
      {
        total_threads: 4567,
        op_confirmed_count: 1234,
        average_quality: 7.1,
        categories: {
          "formula_errors" => 1567,
          "pivot_tables" => 892,
          "vba_macros" => 567,
          "data_analysis" => 734,
          "charts" => 445,
          "formatting" => 362
        },
        quality_tiers: {
          "excellent" => 890,
          "good" => 1567,
          "fair" => 1234,
          "poor" => 876
        },
        last_sync: Time.current - 2.hours
      }
    end
  end

  def fetch_recent_reddit_threads
    # Use actual model data if available, fallback to mock data
    if KnowledgeThread.reddit.exists?
      KnowledgeThread.reddit.recent.limit(10).map do |thread|
        {
          id: thread.external_id,
          title: thread.title,
          op_confirmed: thread.op_confirmed,
          quality_score: thread.quality_score,
          source_url: thread.source_url,
          created_at: thread.processed_at || thread.created_at
        }
      end
    else
      # Mock data for development/testing
      [
        {
          id: "r_1m2cvm2",
          title: "VLOOKUP 함수에서 #N/A 오류 해결 방법",
          op_confirmed: true,
          quality_score: 8.2,
          source_url: "https://reddit.com/r/excel/comments/1m2cvm2/",
          created_at: 1.day.ago
        },
        {
          id: "r_1m1abc3",
          title: "피벗테이블 필터링 문제",
          op_confirmed: false,
          quality_score: 6.8,
          source_url: "https://reddit.com/r/excel/comments/1m1abc3/",
          created_at: 2.days.ago
        }
      ]
    end
  end

  def calculate_quality_distribution
    {
      by_score: [
        { range: "9.0-10.0", count: 234, percentage: 15.2 },
        { range: "8.0-8.9", count: 567, percentage: 36.8 },
        { range: "7.0-7.9", count: 445, percentage: 28.9 },
        { range: "6.0-6.9", count: 234, percentage: 15.2 },
        { range: "0.0-5.9", count: 87, percentage: 5.7 }
      ],
      by_op_confirmation: {
        confirmed: 1234,
        not_confirmed: 3333
      }
    }
  end

  def ensure_admin!
    redirect_to root_path unless current_user&.admin?
  end
end
