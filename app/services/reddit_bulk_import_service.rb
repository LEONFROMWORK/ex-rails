# Reddit 데이터 일괄 가져오기 서비스
# bigdata 시스템에서 생성된 JSONL 파일을 처리하여 데이터베이스에 저장
class RedditBulkImportService
  include ActiveModel::Model

  attr_accessor :imported_count, :error_count, :errors, :skipped_count

  MAX_FILE_SIZE = 100.megabytes
  ALLOWED_CONTENT_TYPES = [ "application/json", "text/plain" ].freeze

  def initialize
    @imported_count = 0
    @error_count = 0
    @skipped_count = 0
    @errors = []
  end

  def self.import_from_file(uploaded_file)
    service = new
    service.import_from_file(uploaded_file)
    service
  end

  def import_from_file(uploaded_file)
    begin
      # 파일 검증
      validate_file(uploaded_file)
      return self unless @errors.empty?

      # 임시 파일에 저장
      temp_file_path = save_temp_file(uploaded_file)

      # JSONL 파일 처리
      process_jsonl_file(temp_file_path)

      Rails.logger.info "Reddit 일괄 가져오기 완료: #{@imported_count}개 가져옴, #{@skipped_count}개 건너뜀, #{@error_count}개 오류"

    rescue => e
      Rails.logger.error "Reddit 일괄 가져오기 실패: #{e.message}"
      @errors << e.message
    ensure
      # 임시 파일 정리
      File.delete(temp_file_path) if temp_file_path && File.exist?(temp_file_path)
    end

    self
  end

  def success?
    @errors.empty? && @imported_count > 0
  end

  def error_message
    @errors.join("; ")
  end

  private

  def validate_file(uploaded_file)
    if uploaded_file.nil?
      @errors << "파일이 선택되지 않았습니다"
      return
    end

    if uploaded_file.size > MAX_FILE_SIZE
      @errors << "파일 크기가 너무 큽니다 (최대 #{MAX_FILE_SIZE / 1.megabyte}MB)"
      return
    end

    unless ALLOWED_CONTENT_TYPES.include?(uploaded_file.content_type)
      @errors << "지원하지 않는 파일 형식입니다 (.jsonl, .json 파일만 가능)"
      return
    end

    original_name = uploaded_file.original_filename.downcase
    unless original_name.end_with?(".jsonl", ".json")
      @errors << "파일 확장자가 올바르지 않습니다 (.jsonl 또는 .json 파일만 가능)"
    end
  end

  def save_temp_file(uploaded_file)
    temp_file_path = Rails.root.join("tmp", "reddit_import_#{SecureRandom.hex(8)}.jsonl")

    File.open(temp_file_path, "wb") do |file|
      uploaded_file.rewind
      file.write(uploaded_file.read)
    end

    temp_file_path
  end

  def process_jsonl_file(file_path)
    File.foreach(file_path).with_index do |line, index|
      begin
        line = line.strip
        next if line.empty?

        reddit_data = JSON.parse(line)

        # Reddit 데이터 검증
        unless valid_reddit_data?(reddit_data)
          @error_count += 1
          @errors << "라인 #{index + 1}: 잘못된 Reddit 데이터 형식"
          next
        end

        # 중복 확인
        external_id = reddit_data.dig("metadata", "submission_id")
        if KnowledgeThread.reddit.exists?(external_id: external_id)
          @skipped_count += 1
          next
        end

        # 스레드 생성
        create_knowledge_thread(reddit_data)
        @imported_count += 1

        # 100개마다 진행 상황 로그
        if (@imported_count % 100).zero?
          Rails.logger.info "Reddit 일괄 가져오기 진행 중: #{@imported_count}개 완료"
        end

      rescue JSON::ParserError => e
        @error_count += 1
        @errors << "라인 #{index + 1}: JSON 파싱 오류 - #{e.message}"
      rescue => e
        @error_count += 1
        @errors << "라인 #{index + 1}: 처리 오류 - #{e.message}"
      end
    end
  end

  def valid_reddit_data?(data)
    return false unless data.is_a?(Hash)

    required_fields = %w[metadata question answer quality_metrics]
    return false unless required_fields.all? { |field| data.key?(field) }

    metadata = data["metadata"]
    return false unless metadata&.key?("submission_id")

    question = data["question"]
    return false unless question&.key?("title") && question&.key?("body")

    answer = data["answer"]
    return false unless answer&.key?("body_markdown")

    quality_metrics = data["quality_metrics"]
    return false unless quality_metrics&.key?("overall_score")

    true
  end

  def create_knowledge_thread(reddit_data)
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

    KnowledgeThread.create!(thread_attrs)
  end

  def extract_category(reddit_data)
    # Reddit 메타데이터에서 카테고리 추출
    tags = reddit_data["question"]["tags"] || []
    title = reddit_data["question"]["title"].downcase
    content = reddit_data["question"]["body"].downcase

    # 키워드 기반 카테고리 매핑
    category_keywords = {
      "formula_errors" => [ "formula", "error", "#n/a", "#ref", "#value", "#div/0", "vlookup", "hlookup", "index", "match" ],
      "formula_functions" => [ "vlookup", "hlookup", "sumif", "countif", "index", "match", "if", "function" ],
      "pivot_tables" => [ "pivot", "table", "summarize", "group" ],
      "vba_macros" => [ "vba", "macro", "code", "script", "automation" ],
      "data_analysis" => [ "analysis", "data", "statistics", "trend", "correlation" ],
      "charts" => [ "chart", "graph", "plot", "visualization", "bar", "line", "pie" ],
      "formatting" => [ "format", "color", "style", "conditional formatting", "cell format" ]
    }

    # 태그 우선 확인
    tags.each do |tag|
      category_keywords.each do |category, keywords|
        return category if keywords.include?(tag.downcase)
      end
    end

    # 제목과 내용에서 키워드 검색
    text_to_search = "#{title} #{content}"
    category_keywords.each do |category, keywords|
      return category if keywords.any? { |keyword| text_to_search.include?(keyword) }
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
      collection_timestamp: reddit_data["metadata"]["collection_timestamp"],
      subreddit: "excel"
    }
  end
end
