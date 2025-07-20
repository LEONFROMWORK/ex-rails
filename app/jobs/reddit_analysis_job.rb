# Reddit 데이터 분석 작업
class RedditAnalysisJob < ApplicationJob
  queue_as :reddit_analysis

  def perform(analysis_type = "quality_check")
    case analysis_type
    when "quality_check"
      perform_quality_analysis
    when "category_classification"
      perform_category_classification
    when "content_similarity"
      perform_content_similarity_analysis
    else
      Rails.logger.warn "Unknown Reddit analysis type: #{analysis_type}"
    end
  end

  private

  def perform_quality_analysis
    Rails.logger.info "Reddit 품질 분석 시작"

    # 품질 점수가 낮은 스레드들을 재분석
    low_quality_threads = KnowledgeThread.reddit
                            .where("quality_score < ?", 5.0)
                            .where("updated_at < ?", 1.week.ago)
                            .limit(100)

    updated_count = 0

    low_quality_threads.find_each do |thread|
      begin
        # 간단한 품질 점수 재계산 (실제로는 AI 분석을 사용할 수 있음)
        new_score = calculate_quality_score(thread)

        if new_score != thread.quality_score
          thread.update!(quality_score: new_score)
          updated_count += 1
        end

      rescue => e
        Rails.logger.error "Reddit 스레드 #{thread.external_id} 품질 분석 실패: #{e.message}"
      end
    end

    Rails.logger.info "Reddit 품질 분석 완료: #{updated_count}개 업데이트"
  end

  def perform_category_classification
    Rails.logger.info "Reddit 카테고리 분류 시작"

    # 카테고리가 'general'인 스레드들을 재분류
    general_threads = KnowledgeThread.reddit
                        .where(category: "general")
                        .where("updated_at < ?", 1.week.ago)
                        .limit(100)

    reclassified_count = 0

    general_threads.find_each do |thread|
      begin
        new_category = classify_thread_category(thread)

        if new_category != "general" && new_category != thread.category
          thread.update!(category: new_category)
          reclassified_count += 1
        end

      rescue => e
        Rails.logger.error "Reddit 스레드 #{thread.external_id} 카테고리 분류 실패: #{e.message}"
      end
    end

    Rails.logger.info "Reddit 카테고리 분류 완료: #{reclassified_count}개 재분류"
  end

  def perform_content_similarity_analysis
    Rails.logger.info "Reddit 콘텐츠 유사도 분석 시작"

    # 중복 가능성이 있는 스레드들을 찾아서 마킹
    recent_threads = KnowledgeThread.reddit
                       .where("created_at > ?", 1.month.ago)
                       .order(:created_at)
                       .limit(500)

    duplicate_pairs = []

    recent_threads.find_each do |thread|
      # 제목 유사도 기반 중복 검사 (실제로는 더 정교한 알고리즘 사용)
      similar_threads = KnowledgeThread.reddit
                          .where.not(id: thread.id)
                          .where("similarity(title, ?) > 0.8", thread.title)
                          .limit(5)

      similar_threads.each do |similar_thread|
        duplicate_pairs << [ thread.id, similar_thread.id ]
      end
    end

    Rails.logger.info "Reddit 콘텐츠 유사도 분석 완료: #{duplicate_pairs.length}개 유사 쌍 발견"
  end

  def calculate_quality_score(thread)
    score = 5.0 # 기본 점수

    # 제목 길이와 품질
    title_length = thread.title.length
    score += 1.0 if title_length > 20 && title_length < 100
    score -= 1.0 if title_length < 10

    # 답변 내용 길이와 품질
    if thread.answer_content.present?
      answer_length = thread.answer_content.length
      score += 1.5 if answer_length > 100
      score += 1.0 if answer_length > 50
      score -= 1.0 if answer_length < 20
    end

    # OP 확인 여부 (Reddit 특화)
    score += 2.0 if thread.op_confirmed?

    # 투표 점수
    if thread.votes > 0
      score += [ thread.votes * 0.1, 2.0 ].min
    elsif thread.votes < 0
      score += [ thread.votes * 0.1, -2.0 ].max
    end

    # 카테고리별 가중치
    case thread.category
    when "formula_errors", "formula_functions"
      score += 0.5 # 인기 카테고리
    when "vba_macros"
      score += 1.0 # 고급 내용
    end

    # 점수 범위 제한 (0.0 ~ 10.0)
    [ [ score, 0.0 ].max, 10.0 ].min.round(1)
  end

  def classify_thread_category(thread)
    title = thread.title.downcase
    question = thread.question_content&.downcase || ""
    answer = thread.answer_content&.downcase || ""

    content = "#{title} #{question} #{answer}"

    # 키워드 기반 분류
    category_patterns = {
      "formula_errors" => [
        /#n\/a/, /#ref/, /#value/, /#div\/0/, /#name\?/, /#null!/,
        /error/, /formula.*error/, /function.*error/
      ],
      "formula_functions" => [
        /vlookup/, /hlookup/, /index.*match/, /sumif/, /countif/, /averageif/,
        /concatenate/, /left/, /right/, /mid/, /len/, /find/, /search/
      ],
      "pivot_tables" => [
        /pivot.*table/, /pivot/, /summarize/, /group.*by/, /aggregat/
      ],
      "vba_macros" => [
        /\bvba\b/, /macro/, /\.vba/, /sub /, /function /, /dim /, /for.*next/
      ],
      "data_analysis" => [
        /analys/, /statistic/, /trend/, /correlation/, /regression/,
        /chart.*data/, /data.*visualization/
      ],
      "charts" => [
        /chart/, /graph/, /plot/, /bar.*chart/, /line.*chart/, /pie.*chart/,
        /scatter/, /histogram/
      ],
      "formatting" => [
        /format/, /conditional.*format/, /color/, /style/, /cell.*format/,
        /number.*format/, /date.*format/
      ]
    }

    # 각 카테고리 패턴과 매칭
    category_patterns.each do |category, patterns|
      return category if patterns.any? { |pattern| content.match?(pattern) }
    end

    "general"
  end

  # 클래스 메서드들
  def self.recent
    where("created_at > ?", 1.week.ago)
      .order(created_at: :desc)
      .includes(:arguments)
  end

  def self.by_analysis_type(type)
    joins("JOIN jsonb_array_elements(arguments) AS arg ON arg->>'analysis_type' = ?", type)
  end
end
