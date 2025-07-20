# frozen_string_literal: true

module Api
  module V1
    class KnowledgeSearchController < BaseController
      before_action :authenticate_user!

      # POST /api/v1/knowledge/search
      # Excel 문제에 대한 해결책 검색
      def search
        result = KnowledgeItemSearchService.call(
          params[:query],
          user: current_user,
          min_similarity: params[:min_similarity],
          include_ai_fallback: params[:include_ai_fallback] != "false"
        )

        if result.success?
          render json: {
            success: true,
            data: result.value,
            search_id: generate_search_id
          }
        else
          render json: {
            success: false,
            error: result.error,
            fallback_options: provide_fallback_options
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/knowledge/report_problem
      # 해결되지 않은 문제 보고
      def report_problem
        result = ProblemReportService.call(
          user: current_user,
          query: params[:query],
          context: params[:context] || "knowledge_search",
          additional_info: problem_report_params
        )

        if result.success?
          render json: {
            success: true,
            report: result.value,
            message: "문제가 성공적으로 보고되었습니다."
          }
        else
          render json: {
            success: false,
            error: result.error
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/knowledge/:id/feedback
      # 해결책에 대한 피드백
      def feedback
        knowledge_item = KnowledgeItem.find(params[:id])

        feedback = knowledge_item.feedbacks.create!(
          user: current_user,
          helpful: params[:helpful],
          rating: params[:rating],
          comment: params[:comment]
        )

        # 품질 점수 업데이트
        update_quality_score(knowledge_item)

        render json: {
          success: true,
          feedback_id: feedback.id,
          updated_quality_score: knowledge_item.reload.quality_score
        }
      end

      # GET /api/v1/knowledge/trending
      # 트렌딩 검색어 및 문제
      def trending
        trending_data = {
          trending_queries: SearchLog.trending_queries(7.days, 10),
          failed_queries: SearchLog.popular_failed_queries(10),
          recent_solutions: recent_high_quality_solutions,
          success_rate: SearchLog.success_rate(30.days)
        }

        render json: {
          success: true,
          data: trending_data
        }
      end

      # GET /api/v1/knowledge/suggest
      # 자동 완성 제안
      def suggest
        query = params[:q]

        suggestions = KnowledgeItem
          .where("question ILIKE ?", "%#{query}%")
          .order(quality_score: :desc, usage_count: :desc)
          .limit(10)
          .pluck(:question)
          .uniq

        render json: {
          success: true,
          suggestions: suggestions
        }
      end

      private

      def problem_report_params
        params.permit(
          :excel_file_id,
          :error_details,
          :affected_users_count,
          :steps_to_reproduce,
          :expected_behavior,
          :actual_behavior,
          screenshots: []
        )
      end

      def generate_search_id
        "search_#{SecureRandom.hex(8)}"
      end

      def provide_fallback_options
        {
          actions: [
            {
              label: "문제 보고하기",
              endpoint: "/api/v1/knowledge/report_problem",
              method: "POST"
            },
            {
              label: "전문가 채팅",
              endpoint: "/api/v1/support/chat",
              method: "GET"
            },
            {
              label: "커뮤니티 질문",
              endpoint: "/api/v1/community/questions",
              method: "GET"
            }
          ],
          helpful_links: [
            {
              title: "Excel 기본 가이드",
              url: "/guides/excel-basics"
            },
            {
              title: "자주 묻는 질문",
              url: "/faq"
            }
          ]
        }
      end

      def update_quality_score(knowledge_item)
        # 피드백 기반 품질 점수 재계산
        feedbacks = knowledge_item.feedbacks
        return if feedbacks.empty?

        helpful_ratio = feedbacks.where(helpful: true).count.to_f / feedbacks.count
        avg_rating = feedbacks.average(:rating) || 0

        # 가중 평균 계산
        new_score = (helpful_ratio * 0.6 + avg_rating / 5.0 * 0.4).round(2)

        knowledge_item.update!(quality_score: new_score)
      end

      def recent_high_quality_solutions
        KnowledgeItem
          .where("quality_score > ?", 0.8)
          .where("created_at > ?", 7.days.ago)
          .order(created_at: :desc)
          .limit(5)
          .select(:id, :question, :quality_score, :usage_count)
      end
    end
  end
end
