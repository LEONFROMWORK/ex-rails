# frozen_string_literal: true

# PipeData에서 전송된 데이터를 ExcelApp-Rails 데이터베이스에 저장하는 서비스
class PipedataIngestionService < ApplicationService
  # 난이도 매핑
  DIFFICULTY_MAPPING = {
    "easy" => 0,
    "medium" => 1,
    "hard" => 2,
    "expert" => 3
  }.freeze

  def initialize(data_items)
    @data_items = data_items
    @results = {
      processed: 0,
      created: 0,
      duplicates: 0,
      errors: 0,
      error_details: []
    }
  end

  def call
    validate_input!

    @data_items.each_with_index do |item, index|
      process_item(item, index)
    end

    create_success_result
  rescue StandardError => e
    Rails.logger.error "PipedataIngestionService error: #{e.message}"
    Result.failure("Failed to process PipeData: #{e.message}").tap do |result|
      result.define_singleton_method(:error_message) { result.error }
      result.define_singleton_method(:error_details) { @results[:error_details] }
    end
  end

  private

  def validate_input!
    unless @data_items.is_a?(Array)
      raise ArgumentError, "Data items must be an array"
    end
  end

  def process_item(item, index)
    @results[:processed] += 1

    # 필수 필드 검증
    unless item[:question].present? && item[:answer].present?
      record_error(index, "Missing required fields: question or answer")
      return
    end

    # 중복 확인
    existing = KnowledgeItem.find_duplicate(item[:question], item[:source])
    if existing
      @results[:duplicates] += 1
      Rails.logger.debug "Duplicate found for question: #{item[:question][0..50]}..."
      return
    end

    # 새 아이템 생성
    create_knowledge_item(item, index)
  rescue StandardError => e
    record_error(index, "Failed to process item: #{e.message}")
  end

  def create_knowledge_item(item, index)
    # 임베딩 생성 (현재는 더미 값, 실제 구현에서는 OpenAI API 호출)
    embedding = generate_embedding(item[:question], item[:answer])

    knowledge_item = KnowledgeItem.create!({
      question: item[:question],
      answer: item[:answer],
      excel_functions: normalize_array_field(item[:excel_functions]),
      code_snippets: normalize_array_field(item[:code_snippets]),
      difficulty: map_difficulty(item[:difficulty]),
      quality_score: item[:quality_score].to_f,
      source: item[:source] || "pipedata_unknown",
      tags: normalize_array_field(item[:tags]),
      embedding: embedding,
      metadata: normalize_metadata(item[:metadata])
    })

    @results[:created] += 1
    Rails.logger.debug "Created KnowledgeItem: #{knowledge_item.id}"
  rescue ActiveRecord::RecordInvalid => e
    record_error(index, "Validation failed: #{e.record.errors.full_messages.join(', ')}")
  rescue StandardError => e
    record_error(index, "Creation failed: #{e.message}")
  end

  def generate_embedding(question, answer)
    # TODO: 실제 구현에서는 OpenAI Embedding API 호출
    # 현재는 더미 임베딩 (1536 dimensions with random values)
    Array.new(1536) { rand(-1.0..1.0) }
  end

  def normalize_array_field(field)
    case field
    when Array then field
    when String then field.present? ? [ field ] : []
    when nil then []
    else []
    end
  end

  def normalize_metadata(metadata)
    case metadata
    when Hash then metadata
    when String
      begin
        JSON.parse(metadata)
      rescue JSON::ParserError
        { original: metadata }
      end
    when nil then {}
    else { original: metadata.to_s }
    end
  end

  def map_difficulty(difficulty)
    difficulty_str = difficulty.to_s.downcase
    DIFFICULTY_MAPPING[difficulty_str] || DIFFICULTY_MAPPING["medium"]
  end

  def record_error(index, message)
    @results[:errors] += 1
    @results[:error_details] << {
      index: index,
      message: message
    }
    Rails.logger.warn "PipeData item #{index} error: #{message}"
  end

  def create_success_result
    message = "Successfully processed #{@results[:processed]} entries: " \
              "#{@results[:created]} created, #{@results[:duplicates]} duplicates, " \
              "#{@results[:errors]} errors"

    @results[:message] = message

    Result.success(@results).tap do |result|
      result.define_singleton_method(:data) { result.value }
    end
  end
end
