# frozen_string_literal: true

module AiIntegration
  module RagSystem
    class RagOrchestrator
      attr_reader :vector_db, :embedding_service

      def initialize
        @vector_db = VectorDatabaseService.new
        @embedding_service = EmbeddingService.new
      end

      def enhance_query_with_rag(query, context: "", limit: 5, search_type: :hybrid)
        Rails.logger.info("RAG enhancement for query: #{query.truncate(100)}")

        # Combine query and context for better search
        search_query = [ query, context ].reject(&:blank?).join(" ")

        # Perform search based on type
        relevant_docs = case search_type
        when :semantic
                         @vector_db.semantic_search(search_query, limit: limit)
        when :keyword
                         @vector_db.keyword_search(search_query, limit: limit)
        when :hybrid
                         @vector_db.hybrid_search(search_query, limit: limit)
        else
                         @vector_db.hybrid_search(search_query, limit: limit)
        end

        # Build enhanced context
        enhanced_context = build_enhanced_context(relevant_docs, query)

        {
          original_query: query,
          enhanced_context: enhanced_context,
          relevant_documents: relevant_docs,
          search_type: search_type,
          documents_found: relevant_docs.size
        }
      end

      def build_rag_prompt(query, context: "", images: nil, tier: "tier1")
        # Get RAG enhancement
        rag_data = enhance_query_with_rag(query, context: context)

        # Build system prompt based on tier
        system_prompt = build_system_prompt(tier)

        # Build user prompt with RAG context
        user_prompt = build_user_prompt(query, context, rag_data, images)

        {
          system_prompt: system_prompt,
          user_prompt: user_prompt,
          rag_data: rag_data,
          total_context_tokens: estimate_tokens(system_prompt + user_prompt)
        }
      end

      def index_excel_knowledge(content, metadata = {})
        # Prepare metadata
        enhanced_metadata = metadata.merge(
          indexed_at: Time.current.iso8601,
          source: metadata[:source] || "excel_knowledge",
          language: detect_language(content),
          content_type: "excel_qa"
        )

        # Store in vector database
        document = @vector_db.store_document(
          content: content,
          metadata: enhanced_metadata
        )

        Rails.logger.info("Indexed Excel knowledge: #{document.id}")
        document
      end

      def batch_index_excel_knowledge(documents)
        enhanced_documents = documents.map do |doc|
          {
            content: doc[:content],
            metadata: doc[:metadata].merge(
              indexed_at: Time.current.iso8601,
              source: doc[:metadata][:source] || "excel_knowledge",
              language: detect_language(doc[:content]),
              content_type: "excel_qa"
            )
          }
        end

        results = @vector_db.batch_store_documents(enhanced_documents)
        Rails.logger.info("Batch indexed #{results.size} Excel knowledge documents")
        results
      end

      def search_excel_knowledge(query, filters = {})
        # Enhanced search with Excel-specific filters
        excel_filters = filters.merge(
          source: "excel_knowledge",
          content_type: "excel_qa"
        )

        @vector_db.hybrid_search(query, limit: 10, filters: excel_filters)
      end

      def get_rag_statistics
        vector_stats = @vector_db.get_statistics
        embedding_stats = @embedding_service.embedding_stats

        {
          vector_database: vector_stats,
          embedding_service: embedding_stats,
          system_status: {
            operational: true,
            last_check: Time.current.iso8601
          }
        }
      end

      def optimize_rag_performance
        # Cleanup old documents
        cleaned_up = @vector_db.cleanup_old_documents

        # Remove duplicates
        RagDocument.cleanup_duplicates

        # Refresh statistics
        stats = get_rag_statistics

        {
          cleanup_results: {
            old_documents_removed: cleaned_up,
            duplicates_removed: true
          },
          updated_statistics: stats
        }
      end

      private

      def build_enhanced_context(relevant_docs, query)
        return "" if relevant_docs.empty?

        context_parts = []

        relevant_docs.each_with_index do |doc, index|
          metadata = doc[:metadata] || {}

          context_parts << <<~CONTEXT
            Reference #{index + 1} (Similarity: #{doc[:similarity]&.round(2) || 'N/A'}):
            Source: #{metadata['source'] || 'Unknown'}
            Functions: #{metadata['functions']&.join(', ') || 'None'}
            Content: #{doc[:content].truncate(300)}
          CONTEXT
        end

        context_parts.join("\n---\n")
      end

      def build_system_prompt(tier)
        base_prompt = "You are an expert Excel assistant with access to a comprehensive knowledge base of Excel Q&A examples."

        case tier
        when "tier3"
          base_prompt + " You have advanced expertise in complex Excel scenarios, VBA, Power Query, and enterprise-level solutions."
        when "tier2"
          base_prompt + " You have intermediate to advanced Excel knowledge and can handle complex formulas and analysis."
        else
          base_prompt + " You provide clear, helpful Excel guidance for common tasks and formulas."
        end
      end

      def build_user_prompt(query, context, rag_data, images)
        prompt_parts = []

        # Add RAG context if available
        if rag_data[:relevant_documents].any?
          prompt_parts << "Based on the following relevant Excel knowledge:"
          prompt_parts << rag_data[:enhanced_context]
          prompt_parts << "---"
        end

        # Add user context
        if context.present?
          prompt_parts << "Context: #{context}"
        end

        # Add image information
        if images&.any?
          prompt_parts << "Note: #{images.size} image(s) provided for additional context."
        end

        # Add main query
        prompt_parts << "Question: #{query}"

        # Add instructions
        prompt_parts << <<~INSTRUCTIONS

          Please provide a comprehensive answer that:
          1. Addresses the specific question
          2. Includes relevant Excel formulas if applicable
          3. Provides step-by-step instructions when helpful
          4. References the knowledge base examples when relevant
          5. Considers the context and any images provided
        INSTRUCTIONS

        prompt_parts.join("\n\n")
      end

      def detect_language(content)
        # Simple heuristic: check for Korean characters
        if content.match?(/[ㄱ-ㅎ가-힣]/)
          "ko"
        else
          "en"
        end
      end

      def estimate_tokens(text)
        # Simple estimation: ~4 characters per token
        (text.length / 4.0).ceil
      end
    end
  end
end
