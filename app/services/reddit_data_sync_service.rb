# Reddit 데이터 동기화 서비스
# bigdata 시스템의 Reddit 수집 데이터를 Rails 애플리케이션으로 동기화
class RedditDataSyncService
  include ActiveModel::Model

  attr_accessor :processed_count, :error_count, :errors

  def initialize
    @processed_count = 0
    @error_count = 0
    @errors = []
  end

  def self.perform_sync
    service = new
    service.perform_sync
    service
  end

  def perform_sync
    begin
      # bigdata 시스템의 출력 데이터 경로
      data_source_path = Rails.application.config.bigdata_output_path || "/Users/kevin/bigdata/data/output"

      # 최신 Reddit 데이터 파일 찾기
      reddit_files = find_reddit_data_files(data_source_path)

      if reddit_files.empty?
        @errors << "Reddit 데이터 파일을 찾을 수 없습니다."
        return self
      end

      reddit_files.each do |file_path|
        process_reddit_file(file_path)
      end

      Rails.logger.info "Reddit 데이터 동기화 완료: #{@processed_count}개 처리, #{@error_count}개 오류"

    rescue => e
      Rails.logger.error "Reddit 데이터 동기화 실패: #{e.message}"
      @errors << e.message
    end

    self
  end

  def success?
    @errors.empty?
  end

  def error_message
    @errors.join("; ")
  end

  private

  def find_reddit_data_files(base_path)
    pattern = File.join(base_path, "*reddit*.jsonl")
    Dir.glob(pattern).select { |f| File.mtime(f) > 24.hours.ago }
  end

  def process_reddit_file(file_path)
    Rails.logger.info "Reddit 파일 처리 시작: #{file_path}"

    File.foreach(file_path).with_index do |line, index|
      begin
        reddit_data = JSON.parse(line.strip)
        process_reddit_thread(reddit_data)
        @processed_count += 1

        # 100개마다 진행 상황 로그
        Rails.logger.info "Reddit 데이터 처리 중: #{@processed_count}개 완료" if (@processed_count % 100).zero?

      rescue JSON::ParserError => e
        @error_count += 1
        @errors << "라인 #{index + 1}: JSON 파싱 오류 - #{e.message}"
      rescue => e
        @error_count += 1
        @errors << "라인 #{index + 1}: 처리 오류 - #{e.message}"
      end
    end
  end

  def process_reddit_thread(reddit_data)
    # Reddit 스레드 데이터를 Rails 모델로 변환
    thread_attrs = {
      external_id: reddit_data["metadata"]["submission_id"],
      source: "reddit",
      title: reddit_data["question"]["title"],
      question_content: reddit_data["question"]["body"],
      answer_content: reddit_data["answer"]["body_markdown"],
      category: extract_category(reddit_data),
      quality_score: reddit_data["quality_metrics"]["overall_score"],
      source_metadata: build_source_metadata(reddit_data),
      op_confirmed: reddit_data["quality_metrics"].dig("reddit_features", "op_confirmed") || false,
      votes: reddit_data["question"]["score"] || 0,
      source_url: reddit_data["metadata"]["source_url"],
      processed_at: Time.current
    }

    # 기존 데이터 확인 후 생성/업데이트
    existing_thread = find_existing_thread(thread_attrs[:external_id], "reddit")

    if existing_thread
      existing_thread.update!(thread_attrs)
      Rails.logger.debug "Reddit 스레드 업데이트: #{thread_attrs[:external_id]}"
    else
      create_new_thread(thread_attrs)
      Rails.logger.debug "Reddit 스레드 생성: #{thread_attrs[:external_id]}"
    end
  end

  def extract_category(reddit_data)
    # Reddit 메타데이터에서 카테고리 추출
    tags = reddit_data["question"]["tags"] || []

    category_mapping = {
      "vlookup" => "formula_functions",
      "pivot-table" => "pivot_tables",
      "vba" => "vba_macros",
      "formula" => "formula_errors",
      "chart" => "charts",
      "conditional-formatting" => "formatting"
    }

    # 태그 기반 카테고리 매핑
    tags.each do |tag|
      mapped_category = category_mapping[tag.downcase]
      return mapped_category if mapped_category
    end

    # 기본 카테고리
    "general"
  end

  def build_source_metadata(reddit_data)
    {
      platform: "reddit",
      submission_id: reddit_data["metadata"]["submission_id"],
      solution_comment_id: reddit_data["metadata"]["solution_comment_id"],
      submission_score: reddit_data["question"]["score"],
      answer_score: reddit_data["answer"]["score"],
      op_confirmed: reddit_data["quality_metrics"].dig("reddit_features", "op_confirmed"),
      solution_type: reddit_data["quality_metrics"].dig("reddit_features", "solution_type"),
      flair: reddit_data["question"]["link_flair_text"],
      collection_timestamp: reddit_data["metadata"]["collection_timestamp"]
    }
  end

  def find_existing_thread(external_id, source)
    KnowledgeThread.find_by(external_id: external_id, source: source)
  end

  def create_new_thread(thread_attrs)
    KnowledgeThread.create!(thread_attrs)
    Rails.logger.info "새 Reddit 스레드 생성됨: #{thread_attrs[:title]}"
  end
end
