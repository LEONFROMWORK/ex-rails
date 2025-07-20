# frozen_string_literal: true

# OpenRouter를 사용한 텍스트 임베딩 생성 서비스
class EmbeddingService < ApplicationService
  include HTTParty

  base_uri "https://openrouter.ai/api/v1"

  # 임베딩 모델 설정
  EMBEDDING_MODELS = {
    default: "openai/text-embedding-ada-002",
    multilingual: "openai/text-embedding-3-small",
    large: "openai/text-embedding-3-large"
  }.freeze

  EMBEDDING_DIMENSIONS = {
    "openai/text-embedding-ada-002" => 1536,
    "openai/text-embedding-3-small" => 1536,
    "openai/text-embedding-3-large" => 3072
  }.freeze

  def initialize(text, model: :default)
    @text = text
    @model = EMBEDDING_MODELS[model]
    @api_key = ENV["OPENROUTER_API_KEY"] || Rails.application.credentials.openrouter_api_key

    validate_inputs!
  end

  def call
    # 캐시 확인
    cached_embedding = fetch_from_cache
    return Result.success(cached_embedding) if cached_embedding

    # OpenRouter API 호출
    response = generate_embedding

    if response.success?
      embedding = parse_embedding(response)
      cache_embedding(embedding)
      Result.success(embedding)
    else
      handle_error(response)
    end
  rescue StandardError => e
    Rails.logger.error("EmbeddingService 오류: #{e.message}")
    Result.failure("임베딩 생성 실패: #{e.message}")
  end

  # 클래스 메서드 (간편 사용)
  def self.generate(text, model: :default)
    new(text, model: model).call
  end

  # 동기 버전 (기존 코드 호환성)
  def self.generate_sync(text, model: :default)
    result = generate(text, model: model)

    if result.success?
      result.value
    else
      Rails.logger.error("임베딩 생성 실패, 더미 데이터 반환: #{result.error}")
      # 실패 시 더미 임베딩 반환 (기존 코드가 깨지지 않도록)
      Array.new(EMBEDDING_DIMENSIONS[EMBEDDING_MODELS[model]], 0.0)
    end
  end

  private

  def validate_inputs!
    raise ArgumentError, "API KEY가 설정되지 않았습니다" unless @api_key.present?
    raise ArgumentError, "텍스트가 비어있습니다" if @text.blank?
    raise ArgumentError, "지원하지 않는 모델입니다" unless @model.present?
  end

  def generate_embedding
    options = {
      headers: {
        "Authorization" => "Bearer #{@api_key}",
        "Content-Type" => "application/json",
        "HTTP-Referer" => Rails.application.config.app_url || "http://localhost:3000",
        "X-Title" => "ExcelApp-Rails"
      },
      body: {
        model: @model,
        input: @text
      }.to_json,
      timeout: 30
    }

    Rails.logger.info("OpenRouter 임베딩 생성 요청: 모델=#{@model}, 텍스트 길이=#{@text.length}")

    self.class.post("/embeddings", options)
  end

  def parse_embedding(response)
    data = response.parsed_response

    # OpenRouter는 OpenAI 형식을 따름
    if data["data"] && data["data"].first && data["data"].first["embedding"]
      embedding = data["data"].first["embedding"]

      # 차원 검증
      expected_dim = EMBEDDING_DIMENSIONS[@model]
      actual_dim = embedding.size

      if actual_dim != expected_dim
        Rails.logger.warn("임베딩 차원 불일치: 예상=#{expected_dim}, 실제=#{actual_dim}")
      end

      # pgvector는 항상 1536 차원을 기대하므로 조정
      if actual_dim > 1536
        embedding[0...1536]
      elsif actual_dim < 1536
        embedding + Array.new(1536 - actual_dim, 0.0)
      else
        embedding
      end
    else
      raise "예상하지 못한 응답 형식: #{data.inspect}"
    end
  end

  def handle_error(response)
    error_data = response.parsed_response
    error_message = error_data["error"]&.[]("message") || "HTTP #{response.code}"

    Rails.logger.error("OpenRouter API 오류: #{error_message}")

    # 특정 오류 처리
    case response.code
    when 429
      Result.failure("API 요청 한도 초과. 잠시 후 다시 시도하세요.")
    when 401
      Result.failure("API 인증 실패. API KEY를 확인하세요.")
    when 400
      Result.failure("잘못된 요청: #{error_message}")
    else
      Result.failure("임베딩 생성 실패: #{error_message}")
    end
  end

  def fetch_from_cache
    cache_key = generate_cache_key
    Rails.cache.read(cache_key)
  end

  def cache_embedding(embedding)
    cache_key = generate_cache_key
    Rails.cache.write(cache_key, embedding, expires_in: 7.days)
  end

  def generate_cache_key
    "embedding:#{@model}:#{Digest::SHA256.hexdigest(@text)}"
  end

  # 배치 처리 지원
  def self.generate_batch(texts, model: :default)
    return [] if texts.empty?

    # OpenRouter는 배치 임베딩을 지원하지 않으므로 순차 처리
    # 하지만 캐시 활용으로 성능 향상
    texts.map { |text| generate_sync(text, model: model) }
  end

  # 비용 추정
  def self.estimate_cost(text_count, model: :default)
    # OpenRouter 가격 (1M 토큰당)
    pricing = {
      "openai/text-embedding-ada-002" => 0.10,
      "openai/text-embedding-3-small" => 0.02,
      "openai/text-embedding-3-large" => 0.13
    }

    model_name = EMBEDDING_MODELS[model]
    price_per_million = pricing[model_name] || 0.10

    # 평균 토큰 수 추정 (한글/영어 혼합 고려)
    avg_tokens_per_text = 500
    total_tokens = text_count * avg_tokens_per_text

    cost = (total_tokens / 1_000_000.0) * price_per_million

    {
      estimated_tokens: total_tokens,
      estimated_cost_usd: cost.round(4),
      model: model_name
    }
  end
end
