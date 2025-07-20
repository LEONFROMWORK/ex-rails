# frozen_string_literal: true

module AiIntegration
  module RagSystem
    class VectorDatabaseService
      include ActionView::Helpers::SanitizeHelper

      attr_reader :client, :embedding_service

      def initialize
        @client = connection
        @embedding_service = EmbeddingService.new
      end

      def store_document(content:, metadata: {})
        # Clean and prepare content
        cleaned_content = sanitize_content(content)

        # Generate embedding
        embedding = @embedding_service.generate_embedding(cleaned_content)

        # Create document record
        document = RagDocument.create!(
          content: cleaned_content,
          metadata: metadata,
          embedding: embedding,
          tokens: count_tokens(cleaned_content)
        )

        Rails.logger.info("Stored document #{document.id} with #{document.credits} tokens")
        document
      end

      def batch_store_documents(documents)
        results = []

        documents.each_slice(10) do |batch|
          batch_results = batch.map do |doc|
            store_document(
              content: doc[:content],
              metadata: doc[:metadata] || {}
            )
          end
          results.concat(batch_results)

          # Rate limiting
          sleep(0.1) if batch_results.size > 5
        end

        Rails.logger.info("Batch stored #{results.size} documents")
        results
      end

      def semantic_search(query, limit: 5, similarity_threshold: 0.7)
        # Generate query embedding
        query_embedding = @embedding_service.generate_embedding(query)

        # Perform vector similarity search
        results = RagDocument.nearest_neighbors(
          :embedding,
          query_embedding,
          distance: "cosine"
        ).limit(limit)

        # Filter by similarity threshold
        filtered_results = results.select do |doc|
          similarity = calculate_similarity(query_embedding, doc.embedding)
          similarity >= similarity_threshold
        end

        # Format results
        format_search_results(filtered_results, query)
      end

      def hybrid_search(query, limit: 5, similarity_threshold: 0.7, filters: {})
        # Combine semantic and keyword search
        semantic_results = semantic_search(query, limit: limit * 2, similarity_threshold: similarity_threshold)
        keyword_results = keyword_search(query, limit: limit * 2, filters: filters)

        # Merge and rank results
        combined_results = merge_search_results(semantic_results, keyword_results)

        # Return top results
        combined_results.first(limit)
      end

      def keyword_search(query, limit: 5, filters: {})
        # Build search query
        base_query = RagDocument.all

        # Apply filters
        if filters[:functions]&.any?
          functions_filter = filters[:functions].map { |f| "%#{f.downcase}%" }
          base_query = base_query.where(
            functions_filter.map { "LOWER(content) LIKE ?" }.join(" OR "),
            *functions_filter
          )
        end

        if filters[:difficulty]
          base_query = base_query.where("metadata->>'difficulty' = ?", filters[:difficulty])
        end

        if filters[:source]
          base_query = base_query.where("metadata->>'source' = ?", filters[:source])
        end

        # Full-text search
        search_terms = extract_search_terms(query)
        if search_terms.any?
          tsquery = search_terms.map { |term| "#{term}:*" }.join(" & ")
          base_query = base_query.where(
            "to_tsvector('english', content) @@ to_tsquery('english', ?)",
            tsquery
          )
        end

        # Execute and format results
        results = base_query.limit(limit).order(created_at: :desc)
        format_search_results(results, query)
      end

      def get_statistics
        {
          total_documents: RagDocument.count,
          total_tokens: RagDocument.sum(:credits),
          average_tokens: RagDocument.average(:credits)&.round(2),
          recent_documents: RagDocument.where(created_at: 1.week.ago..Time.current).count,
          sources: RagDocument.distinct.pluck("metadata->>'source'").compact,
          languages: RagDocument.distinct.pluck("metadata->>'language'").compact
        }
      end

      def delete_document(id)
        document = RagDocument.find(id)
        document.destroy!
        Rails.logger.info("Deleted document #{id}")
        true
      end

      def cleanup_old_documents(older_than: 6.months)
        deleted_count = RagDocument.where(created_at: ..older_than.ago).delete_all
        Rails.logger.info("Cleaned up #{deleted_count} old documents")
        deleted_count
      end

      private

      def connection
        ActiveRecord::Base.connection
      end

      def sanitize_content(content)
        # Remove HTML tags and clean text
        cleaned = sanitize(content, tags: [])

        # Remove excessive whitespace
        cleaned = cleaned.gsub(/\s+/, " ").strip

        # Limit content length
        cleaned.truncate(5000)
      end

      def count_tokens(text)
        # Simple token estimation: ~4 characters per token
        (text.length / 4.0).ceil
      end

      def calculate_similarity(embedding1, embedding2)
        # Cosine similarity calculation
        dot_product = embedding1.zip(embedding2).sum { |a, b| a * b }
        magnitude1 = Math.sqrt(embedding1.sum { |a| a * a })
        magnitude2 = Math.sqrt(embedding2.sum { |a| a * a })

        return 0.0 if magnitude1 == 0 || magnitude2 == 0

        dot_product / (magnitude1 * magnitude2)
      end

      def format_search_results(results, query)
        results.map do |doc|
          {
            id: doc.id,
            content: doc.content,
            metadata: doc.metadata,
            similarity: calculate_similarity_score(doc, query),
            tokens: doc.credits,
            created_at: doc.created_at
          }
        end
      end

      def calculate_similarity_score(doc, query)
        # Generate query embedding and calculate similarity
        query_embedding = @embedding_service.generate_embedding(query)
        calculate_similarity(query_embedding, doc.embedding)
      end

      def merge_search_results(semantic_results, keyword_results)
        # Combine results with different weights
        combined = {}

        # Add semantic results with higher weight
        semantic_results.each do |result|
          combined[result[:id]] = result.merge(
            score: result[:similarity] * 0.7,
            search_type: "semantic"
          )
        end

        # Add keyword results with lower weight
        keyword_results.each do |result|
          if combined[result[:id]]
            # Boost score if found in both searches
            combined[result[:id]][:score] += 0.3
            combined[result[:id]][:search_type] = "hybrid"
          else
            combined[result[:id]] = result.merge(
              score: 0.3,
              search_type: "keyword"
            )
          end
        end

        # Sort by combined score
        combined.values.sort_by { |r| -r[:score] }
      end

      def extract_search_terms(query)
        # Extract meaningful terms from query
        terms = query.downcase.split(/\W+/)

        # Remove common words
        stopwords = %w[the a an and or but in on at to for of with by]
        terms = terms.reject { |term| stopwords.include?(term) || term.length < 2 }

        # Return unique terms
        terms.uniq
      end
    end
  end
end
