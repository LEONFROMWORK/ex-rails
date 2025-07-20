# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_documents
#
#  id               :bigint           not null, primary key
#  content          :text             not null
#  metadata         :jsonb            not null
#  embedding_text   :text             not null
#  tokens           :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_rag_documents_on_metadata   (metadata) USING gin
#  index_rag_documents_on_tokens     (tokens)
#
class RagDocument < ApplicationRecord
  # For now, we'll handle embeddings as text until pgvector is properly configured
  # include Neighbor::Model
  # has_neighbors :embedding, dimensions: 1536

  # Validations
  validates :content, presence: true, length: { minimum: 10, maximum: 10000 }
  validates :credits, presence: true, numericality: { greater_than: 0 }
  validates :metadata, presence: true
  validates :embedding_text, presence: true

  # Scopes
  scope :by_source, ->(source) { where("metadata->>'source' = ?", source) }
  scope :by_language, ->(language) { where("metadata->>'language' = ?", language) }
  scope :by_difficulty, ->(difficulty) { where("metadata->>'difficulty' = ?", difficulty) }
  scope :recent, -> { where(created_at: 1.week.ago..Time.current) }
  scope :with_functions, ->(functions) {
    where(functions.map { "LOWER(content) LIKE ?" }.join(" OR "),
          *functions.map { |f| "%#{f.downcase}%" })
  }

  # Callbacks
  before_validation :sanitize_content
  before_validation :extract_metadata
  before_save :calculate_tokens

  # Instance methods
  def source
    metadata["source"]
  end

  def language
    metadata["language"] || "en"
  end

  def difficulty
    metadata["difficulty"] || "medium"
  end

  def functions
    metadata["functions"] || []
  end

  def excel_elements
    metadata["excel_elements"] || []
  end

  def embedding
    return [] unless embedding_text.present?
    JSON.parse(embedding_text)
  rescue JSON::ParserError
    []
  end

  def embedding=(array)
    self.embedding_text = array.to_json
  end

  def similarity_to(other_embedding)
    return 0.0 unless embedding.present? && other_embedding.present?

    # Cosine similarity
    dot_product = embedding.zip(other_embedding).sum { |a, b| a * b }
    magnitude1 = Math.sqrt(embedding.sum { |a| a * a })
    magnitude2 = Math.sqrt(other_embedding.sum { |a| a * a })

    return 0.0 if magnitude1 == 0 || magnitude2 == 0

    dot_product / (magnitude1 * magnitude2)
  end

  def to_search_result
    {
      id: id,
      content: content,
      metadata: metadata,
      tokens: tokens,
      similarity: nil, # Will be calculated during search
      created_at: created_at
    }
  end

  # Class methods
  def self.search_by_content(query, limit: 10)
    where("content ILIKE ?", "%#{query}%").limit(limit)
  end

  def self.search_by_metadata(key, value, limit: 10)
    where("metadata->>? = ?", key, value).limit(limit)
  end

  def self.full_text_search(query, limit: 10)
    search_terms = query.downcase.split(/\W+/).reject { |term| term.length < 2 }
    return none if search_terms.empty?

    tsquery = search_terms.map { |term| "#{term}:*" }.join(" & ")
    where("to_tsvector('english', content) @@ to_tsquery('english', ?)", tsquery)
      .limit(limit)
      .order(created_at: :desc)
  end

  def self.semantic_search(query_embedding, limit: 10, threshold: 0.7)
    # For now, use a simple approach without pgvector
    # This should be replaced with proper vector search when pgvector is configured
    all_docs = all.to_a

    # Calculate similarities
    docs_with_similarity = all_docs.map do |doc|
      similarity = doc.similarity_to(query_embedding)
      [ doc, similarity ]
    end

    # Filter by threshold and sort
    docs_with_similarity
      .select { |doc, similarity| similarity >= threshold }
      .sort_by { |doc, similarity| -similarity }
      .first(limit)
      .map { |doc, similarity| doc }
  end

  def self.batch_import(documents)
    transaction do
      documents.each_slice(100) do |batch|
        import_batch(batch)
      end
    end
  end

  def self.cleanup_duplicates
    # Find and remove duplicate content
    duplicate_groups = group(:content).having("COUNT(*) > 1").count

    duplicate_groups.each do |content, count|
      duplicates = where(content: content).order(:created_at)
      duplicates.offset(1).destroy_all # Keep the oldest one
    end
  end

  def self.statistics
    {
      total_count: count,
      total_tokens: sum(:credits),
      average_tokens: average(:credits)&.round(2),
      sources: distinct.pluck("metadata->>'source'").compact.sort,
      languages: distinct.pluck("metadata->>'language'").compact.sort,
      difficulties: distinct.pluck("metadata->>'difficulty'").compact.sort,
      recent_count: recent.count,
      size_distribution: {
        small: where(tokens: 0..100).count,
        medium: where(tokens: 101..500).count,
        large: where(tokens: 501..1000).count,
        xlarge: where(tokens: 1001..).count
      }
    }
  end

  private

  def sanitize_content
    return unless content.present?

    # Remove HTML tags and normalize whitespace
    self.content = ActionController::Base.helpers.sanitize(content, tags: [])
    self.content = content.gsub(/\s+/, " ").strip

    # Limit content length
    self.content = content.truncate(5000) if content.length > 5000
  end

  def extract_metadata
    return unless content.present?

    self.metadata ||= {}

    # Extract Excel functions
    excel_functions = extract_excel_functions(content)
    self.metadata["functions"] = excel_functions if excel_functions.any?

    # Extract cell references
    cell_references = extract_cell_references(content)
    self.metadata["excel_elements"] = cell_references if cell_references.any?

    # Auto-detect language (simple heuristic)
    self.metadata["language"] ||= detect_language(content)

    # Auto-detect difficulty based on content complexity
    self.metadata["difficulty"] ||= detect_difficulty(content)
  end

  def calculate_tokens
    return unless content.present?

    # Simple token estimation: ~4 characters per token
    self.credits = (content.length / 4.0).ceil
  end

  def extract_excel_functions(text)
    excel_functions = %w[
      SUM AVERAGE COUNT MAX MIN IF VLOOKUP HLOOKUP INDEX MATCH
      SUMIF SUMIFS COUNTIF COUNTIFS ROUND ABS AND OR NOT IFERROR
      XLOOKUP FILTER SORT UNIQUE TEXTJOIN CONCATENATE LEFT RIGHT
      MID LEN DATE TODAY NOW YEAR MONTH DAY WEEKDAY PIVOT
    ]

    found_functions = []
    excel_functions.each do |func|
      if text.upcase.include?(func)
        found_functions << func
      end
    end

    found_functions.uniq
  end

  def extract_cell_references(text)
    # Extract cell references like A1, B2:C10, etc.
    cell_pattern = /\b[A-Z]+\d+(?::[A-Z]+\d+)?\b/
    text.scan(cell_pattern).uniq
  end

  def detect_language(text)
    # Simple heuristic: check for Korean characters
    if text.match?(/[ㄱ-ㅎ가-힣]/)
      "ko"
    else
      "en"
    end
  end

  def detect_difficulty(text)
    complexity_score = 0

    # Length factor
    complexity_score += 1 if text.length > 500
    complexity_score += 1 if text.length > 1000

    # Formula complexity
    complex_functions = %w[VLOOKUP HLOOKUP INDEX MATCH SUMIFS COUNTIFS XLOOKUP]
    complex_functions.each do |func|
      complexity_score += 1 if text.upcase.include?(func)
    end

    # Nested functions
    complexity_score += 1 if text.match?(/\w+\(\w+\(/)

    # Multiple conditions
    complexity_score += 1 if text.include?("AND") || text.include?("OR")

    case complexity_score
    when 0..1 then "simple"
    when 2..3 then "medium"
    when 4..5 then "complex"
    else "expert"
    end
  end

  def self.import_batch(batch)
    values = batch.map do |doc|
      "(#{connection.quote(doc[:content])}, #{connection.quote(doc[:metadata].to_json)}, #{connection.quote(doc[:embedding])}, #{doc[:credits]}, NOW(), NOW())"
    end

    sql = "INSERT INTO rag_documents (content, metadata, embedding, tokens, created_at, updated_at) VALUES #{values.join(', ')}"
    connection.execute(sql)
  end
end
