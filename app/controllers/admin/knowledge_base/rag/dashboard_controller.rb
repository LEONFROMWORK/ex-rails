# frozen_string_literal: true

module Admin
  module KnowledgeBase
    module Rag
      class DashboardController < ApplicationController
        before_action :require_admin!

        def index
          @rag_stats = fetch_rag_stats
          @search_metrics = fetch_search_metrics
          @vector_indices = fetch_vector_indices
          @embedding_jobs = fetch_embedding_jobs
        end

        def stats
          render json: {
            success: true,
            stats: fetch_rag_stats
          }
        end

        def metrics
          render json: {
            success: true,
            metrics: fetch_search_metrics
          }
        end

        def indices
          render json: {
            success: true,
            indices: fetch_vector_indices
          }
        end

        def test_search
          query = params[:query]

          if query.blank?
            render json: { error: "검색 쿼리가 필요합니다" }, status: :bad_request
            return
          end

          results = perform_rag_search_test(query)

          render json: {
            success: true,
            results: results
          }
        end

        private

        def fetch_rag_stats
          {
            total_vectors: 15420,
            vector_dimensions: 1536,
            index_size: "2.4 GB",
            search_latency: 45,
            retrieval_accuracy: 94.2,
            embedding_model: "text-embedding-3-small",
            vector_store: "Chroma DB"
          }
        end

        def fetch_search_metrics
          {
            total_searches: 12890,
            avg_response_time: 42,
            success_rate: 98.7,
            popular_queries: [
              { query: "VLOOKUP 오류", count: 342 },
              { query: "피벗테이블 만들기", count: 298 },
              { query: "조건부 서식", count: 267 },
              { query: "INDEX MATCH", count: 234 },
              { query: "매크로 실행", count: 189 }
            ],
            category_usage: {
              "함수오류" => 42.3,
              "데이터처리" => 28.7,
              "차트생성" => 15.2,
              "매크로/VBA" => 8.9,
              "기타" => 4.9
            }
          }
        end

        def fetch_vector_indices
          [
            {
              id: "index_excel_qa_main",
              name: "Excel Q&A Main Index",
              type: "HNSW",
              documents: 15420,
              size: "2.4 GB",
              last_updated: 6.hours.ago,
              status: "healthy",
              accuracy: 94.2
            },
            {
              id: "index_excel_qa_categories",
              name: "Excel Q&A Categories",
              type: "IVF",
              documents: 15420,
              size: "890 MB",
              last_updated: 6.hours.ago,
              status: "healthy",
              accuracy: 91.8
            },
            {
              id: "index_excel_functions",
              name: "Excel Functions Specific",
              type: "Flat",
              documents: 8945,
              size: "1.2 GB",
              last_updated: 12.hours.ago,
              status: "degraded",
              accuracy: 87.3
            }
          ]
        end

        def fetch_embedding_jobs
          [
            {
              id: "embed_001",
              type: "incremental",
              status: "running",
              progress: 67,
              documents_processed: 1580,
              total_documents: 2340,
              started_at: 25.minutes.ago
            },
            {
              id: "embed_002",
              type: "full_reindex",
              status: "completed",
              progress: 100,
              documents_processed: 15420,
              total_documents: 15420,
              started_at: 2.days.ago,
              completed_at: 2.days.ago + 45.minutes
            },
            {
              id: "embed_003",
              type: "cleanup",
              status: "completed",
              progress: 100,
              documents_processed: 342,
              total_documents: 342,
              started_at: 5.days.ago,
              completed_at: 5.days.ago + 8.minutes
            }
          ]
        end

        def perform_rag_search_test(query)
          # Simulate RAG search test
          start_time = Time.current

          # Mock search results
          documents = [
            {
              id: "doc_001",
              similarity: 0.94,
              question: "VLOOKUP 함수에서 #N/A 오류가 발생합니다",
              answer: "VLOOKUP #N/A 오류는 여러 원인으로 발생할 수 있습니다...",
              category: "함수오류",
              source: "stackoverflow"
            },
            {
              id: "doc_002",
              similarity: 0.89,
              question: "VLOOKUP 대신 사용할 수 있는 다른 함수는?",
              answer: "VLOOKUP 대신 INDEX와 MATCH 함수를 조합하여 사용할 수 있습니다...",
              category: "함수대안",
              source: "reddit"
            }
          ]

          generated_answer = generate_mock_answer(query, documents)
          quality_metrics = evaluate_search_quality(query, documents, generated_answer)

          total_time = ((Time.current - start_time) * 1000).round

          {
            query: query,
            documents: documents,
            generated_answer: generated_answer,
            metrics: {
              query_embedding_time: 120,
              search_time: 35,
              context_building_time: 15,
              generation_time: 890,
              total_time: total_time,
              documents_retrieved: documents.length
            },
            quality_metrics: quality_metrics,
            timestamp: Time.current.iso8601
          }
        end

        def generate_mock_answer(query, documents)
          if query.include?("VLOOKUP") && query.include?("오류")
            "VLOOKUP 함수 오류 해결을 위한 단계별 가이드:\n\n1. **데이터 형식 확인**: 검색값과 테이블의 데이터 형식이 일치하는지 확인하세요.\n2. **정확한 일치 설정**: 네 번째 인수를 FALSE로 설정하여 정확한 일치를 사용하세요.\n3. **오류 처리**: =IFERROR(VLOOKUP(...), \"찾을 수 없음\") 형식으로 오류를 처리하세요."
          else
            "질문에 대한 답변을 검색된 정보를 바탕으로 생성했습니다. 더 구체적인 도움이 필요하시면 상세한 상황을 알려주시기 바랍니다."
          end
        end

        def evaluate_search_quality(query, documents, answer)
          avg_similarity = documents.sum { |doc| doc[:similarity] } / documents.length
          relevance_score = (avg_similarity * 100).round(1)

          {
            relevance_score: relevance_score,
            answer_quality: 85.4,
            diversity_score: 78.9,
            completeness_score: 82.1,
            overall_score: 83.1,
            recommendations: [ "전반적인 성능이 우수합니다" ]
          }
        end
      end
    end
  end
end
