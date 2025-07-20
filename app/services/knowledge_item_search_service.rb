# frozen_string_literal: true

# KnowledgeItem 검색 및 폴백 처리 서비스
class KnowledgeItemSearchService < ApplicationService
  # 최소 유사도 임계값
  MIN_SIMILARITY_THRESHOLD = 0.7
  # 검색 결과 최대 개수
  MAX_RESULTS = 10
  # AI 폴백 제공자
  AI_PROVIDERS = %w[openai anthropic gemini].freeze

  def initialize(query, options = {})
    @query = query
    @options = options
    @min_similarity = options[:min_similarity] || MIN_SIMILARITY_THRESHOLD
    @max_results = options[:max_results] || MAX_RESULTS
    @include_ai_fallback = options[:include_ai_fallback] != false
    @user = options[:user]
  end

  def call
    # 1. KnowledgeItem에서 검색
    knowledge_results = search_knowledge_base

    # 2. 결과 평가
    if sufficient_results?(knowledge_results)
      # 충분한 결과가 있는 경우
      handle_successful_search(knowledge_results)
    else
      # 결과가 부족한 경우 폴백 처리
      handle_insufficient_results(knowledge_results)
    end
  end

  private

  def search_knowledge_base
    # 쿼리 임베딩 생성
    query_embedding = generate_embedding(@query)

    # pgvector를 사용한 유사도 검색
    results = KnowledgeItem
      .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
      .where("1 - (embedding <=> ?) > ?", query_embedding, @min_similarity)
      .includes(:tags)
      .limit(@max_results)

    # 결과에 유사도 점수 추가
    results.map do |item|
      {
        item: item,
        similarity: 1 - item.neighbor_distance,
        confidence: calculate_confidence(item)
      }
    end
  rescue StandardError => e
    Rails.logger.error("KnowledgeItem 검색 실패: #{e.message}")
    []
  end

  def sufficient_results?(results)
    return false if results.empty?

    # 높은 유사도 결과가 3개 이상 있는지 확인
    high_quality_results = results.select { |r| r[:similarity] > 0.85 }
    high_quality_results.size >= 3
  end

  def handle_successful_search(results)
    # 검색 로그 기록
    log_search_event("knowledge_base_hit", results.size)

    # 결과 포맷팅
    formatted_results = format_results(results)

    Result.success({
      source: "knowledge_base",
      results: formatted_results,
      confidence: calculate_overall_confidence(results),
      message: "#{results.size}개의 관련 해결책을 찾았습니다."
    })
  end

  def handle_insufficient_results(knowledge_results)
    fallback_strategies = []

    # 1. 부분 매칭 시도
    partial_results = try_partial_matching
    fallback_strategies << partial_results if partial_results.any?

    # 2. 관련 문서/가이드 검색
    documentation_results = search_documentation
    fallback_strategies << documentation_results if documentation_results.any?

    # 3. AI 폴백 (옵션)
    if @include_ai_fallback
      ai_response = generate_ai_fallback
      fallback_strategies << ai_response if ai_response
    end

    # 4. 유사 문제 제안
    similar_problems = suggest_similar_problems

    # 5. 문제 보고 옵션 제공
    report_option = create_problem_report_option

    # 검색 실패 로그
    log_search_event("knowledge_base_miss", knowledge_results.size)

    Result.success({
      source: "fallback",
      knowledge_results: format_results(knowledge_results),
      fallback_results: fallback_strategies,
      similar_problems: similar_problems,
      report_option: report_option,
      confidence: "low",
      message: build_fallback_message(knowledge_results, fallback_strategies)
    })
  end

  def try_partial_matching
    # 키워드 추출
    keywords = extract_keywords(@query)

    # 키워드 기반 검색
    results = KnowledgeItem
      .joins(:tags)
      .where("question ILIKE ANY(ARRAY[?]) OR answer ILIKE ANY(ARRAY[?])",
             keywords.map { |k| "%#{k}%" },
             keywords.map { |k| "%#{k}%" })
      .distinct
      .limit(5)

    results.map do |item|
      {
        type: "partial_match",
        item: item,
        relevance: calculate_keyword_relevance(item, keywords)
      }
    end
  end

  def search_documentation
    # 외부 문서나 가이드 검색 (Elasticsearch 등 활용 가능)
    docs = []

    # Excel 공식 문서 링크
    excel_functions = extract_excel_functions(@query)
    if excel_functions.any?
      excel_functions.each do |func|
        docs << {
          type: "official_documentation",
          title: "Excel #{func} 함수 공식 문서",
          url: "https://support.microsoft.com/ko-kr/office/#{func.downcase}-function",
          relevance: 0.7
        }
      end
    end

    # 일반적인 Excel 가이드
    if @query.match?(/피벗|pivot/i)
      docs << {
        type: "guide",
        title: "Excel 피벗 테이블 완벽 가이드",
        url: "/guides/excel-pivot-tables",
        relevance: 0.8
      }
    end

    docs
  end

  def generate_ai_fallback
    return nil unless @user&.ai_enabled?

    # 이미지가 첨부된 경우 멀티모달 분석 우선
    if @options[:image_data].present?
      return generate_multimodal_fallback(@options[:image_data])
    end

    # AI 서비스 선택 (사용자 설정 또는 기본값)
    ai_service = select_ai_service

    prompt = build_ai_prompt(@query)

    begin
      response = ai_service.generate_response(prompt)

      {
        type: "ai_generated",
        provider: ai_service.provider_name,
        content: response,
        disclaimer: "이 답변은 AI가 생성한 것으로, 정확성을 보장하지 않습니다.",
        confidence: 0.6
      }
    rescue StandardError => e
      Rails.logger.error("AI 폴백 생성 실패: #{e.message}")
      nil
    end
  end

  def generate_multimodal_fallback(image_data)
    coordinator = AiIntegration::Services::MultimodalCoordinatorService.new(
      user: @user,
      default_tier: :cost_effective,
      quality_threshold: 0.65
    )

    # Excel 스크린샷 분석
    result = coordinator.analyze_excel_screenshot(
      image_data: image_data,
      context: {
        specific_question: @query,
        source: "knowledge_search_fallback"
      }
    )

    if result[:success] && result[:confidence_score] >= 0.6
      {
        type: "multimodal_ai_analysis",
        provider: "openrouter",
        model: result[:model_used],
        content: result[:analysis],
        structured_data: result[:structured_data],
        confidence: result[:confidence_score],
        disclaimer: "이미지 분석 기반 AI 답변입니다. 정확성을 확인해 주세요.",
        quality_tier: result[:quality_metrics][:quality_tier],
        fallback_info: result[:fallback_info]
      }
    else
      Rails.logger.warn("멀티모달 분석 품질 미달 또는 실패")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("멀티모달 폴백 생성 실패: #{e.message}")
    nil
  end

  def suggest_similar_problems
    # 자주 검색되는 유사 문제 제안
    similar_queries = SearchLog
      .where("created_at > ?", 30.days.ago)
      .where("query_embedding <=> ? < ?", generate_embedding(@query), 0.5)
      .group(:query)
      .order("COUNT(*) DESC")
      .limit(5)
      .pluck(:query)

    similar_queries.map do |query|
      {
        query: query,
        search_url: "/search?q=#{CGI.escape(query)}"
      }
    end
  end

  def create_problem_report_option
    {
      type: "report_problem",
      title: "해결책을 찾지 못하셨나요?",
      description: "이 문제를 전문가에게 보고하고 답변을 받아보세요.",
      actions: [
        {
          label: "문제 보고하기",
          url: "/problems/new",
          params: {
            query: @query,
            context: "knowledge_base_miss"
          }
        },
        {
          label: "커뮤니티에 질문하기",
          url: "/community/questions/new",
          params: {
            title: @query,
            tags: extract_keywords(@query)
          }
        }
      ]
    }
  end

  def format_results(results)
    results.map do |result|
      item = result[:item]
      {
        id: item.id,
        question: item.question,
        answer: item.answer,
        excel_functions: item.excel_functions,
        code_snippets: item.code_snippets,
        tags: item.tags,
        difficulty: item.difficulty,
        quality_score: item.quality_score,
        similarity: result[:similarity],
        confidence: result[:confidence]
      }
    end
  end

  def calculate_confidence(item)
    # 품질 점수와 사용 횟수 기반 신뢰도 계산
    base_confidence = item.quality_score || 0.5
    usage_boost = Math.log10(item.usage_count + 1) * 0.1

    [ base_confidence + usage_boost, 1.0 ].min
  end

  def calculate_overall_confidence(results)
    return "none" if results.empty?

    avg_similarity = results.sum { |r| r[:similarity] } / results.size

    case avg_similarity
    when 0.9..1.0 then "very_high"
    when 0.8..0.9 then "high"
    when 0.7..0.8 then "medium"
    else "low"
    end
  end

  def build_fallback_message(knowledge_results, fallback_strategies)
    if knowledge_results.empty?
      "관련된 해결책을 찾을 수 없었습니다. "
    else
      "#{knowledge_results.size}개의 부분적으로 일치하는 결과를 찾았습니다. "
    end +

    if fallback_strategies.any?
      "추가로 #{fallback_strategies.size}개의 대안을 제공합니다."
    else
      "다른 검색어로 시도하거나 문제를 보고해 주세요."
    end
  end

  def extract_keywords(query)
    # 간단한 키워드 추출 (실제로는 더 정교한 NLP 사용)
    stop_words = %w[the a an and or but in on at to for of with]

    query.downcase
      .split(/\W+/)
      .reject { |word| stop_words.include?(word) || word.length < 3 }
      .uniq
  end

  def extract_excel_functions(query)
    # Excel 함수명 추출
    function_pattern = /\b(SUM|AVERAGE|IF|VLOOKUP|INDEX|MATCH|COUNT|MAX|MIN)\b/i
    query.scan(function_pattern).flatten.map(&:upcase).uniq
  end

  def calculate_keyword_relevance(item, keywords)
    matched_keywords = keywords.count do |keyword|
      item.question.downcase.include?(keyword) ||
      item.answer.downcase.include?(keyword)
    end

    matched_keywords.to_f / keywords.size
  end

  def select_ai_service
    # 사용자 선호도 또는 가용성에 따라 AI 서비스 선택
    provider = @user&.preferred_ai_provider || "openai"

    case provider
    when "openai"
      OpenAIService.new
    when "anthropic"
      AnthropicService.new
    when "gemini"
      GeminiService.new
    else
      OpenAIService.new # 기본값
    end
  end

  def build_ai_prompt(query)
    <<~PROMPT
      Excel 전문가로서 다음 문제에 대한 해결책을 제시해주세요:

      문제: #{query}

      다음 형식으로 답변해주세요:
      1. 문제 이해: 간단한 문제 요약
      2. 해결 방법: 단계별 해결 방법
      3. 예제: 실제 Excel 수식이나 단계
      4. 주의사항: 흔한 실수나 주의점

      답변은 명확하고 실용적이어야 합니다.
    PROMPT
  end

  def generate_embedding(text)
    # OpenRouter.ai 또는 다른 임베딩 서비스 사용
    EmbeddingService.generate(text)
  rescue StandardError => e
    Rails.logger.error("임베딩 생성 실패: #{e.message}")
    Array.new(1536, 0) # 실패 시 제로 벡터
  end

  def log_search_event(event_type, result_count)
    SearchLog.create!(
      user: @user,
      query: @query,
      event_type: event_type,
      result_count: result_count,
      query_embedding: generate_embedding(@query),
      timestamp: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("검색 로그 기록 실패: #{e.message}")
  end
end
