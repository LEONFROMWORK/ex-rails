# frozen_string_literal: true

module AiIntegration
  class MultimodalController < ApplicationController
    before_action :authenticate_user!
    before_action :check_user_tokens

    # 이미지 + 텍스트 분석
    def analyze_image
      return render_error("이미지와 텍스트 프롬프트가 필요합니다", :bad_request) unless valid_image_request?

      begin
        gemini_service = AiIntegration::Services::GeminiMultimodalService.new

        result = gemini_service.analyze_image_with_context(
          image_data: extract_image_data,
          text_prompt: params[:prompt],
          user: current_user,
          context: build_analysis_context
        )

        if result[:analysis]
          # 사용량 추적
          track_multimodal_usage(result)

          render json: {
            success: true,
            analysis: result[:analysis],
            structured_analysis: result[:structured_analysis],
            confidence_score: result[:confidence_score],
            credits_used: result[:credits_used],
            cost_savings: result[:cost_saved],
            provider: result[:provider],
            processing_time: result[:processing_time]
          }
        else
          render_error("이미지 분석에 실패했습니다", :unprocessable_entity)
        end

      rescue StandardError => e
        Rails.logger.error("Multimodal image analysis failed: #{e.message}")
        render_error("이미지 분석 중 오류가 발생했습니다: #{e.message}", :internal_server_error)
      end
    end

    # 비디오 분석 (Gemini 전용 기능)
    def analyze_video
      return render_error("비디오 파일이 필요합니다", :bad_request) unless valid_video_request?

      begin
        gemini_service = AiIntegration::Services::GeminiMultimodalService.new

        video_data = extract_video_data
        duration = extract_video_duration

        # 2시간 제한 체크
        if duration && duration > 7200
          return render_error("비디오는 최대 2시간까지 분석 가능합니다", :bad_request)
        end

        result = gemini_service.analyze_excel_tutorial_video(
          video_data: video_data,
          user: current_user,
          duration_seconds: duration
        )

        if result[:error]
          render_error(result[:message], :unprocessable_entity)
        else
          # 사용량 추적
          track_video_usage(result, duration)

          render json: {
            success: true,
            tutorial_analysis: result[:tutorial_analysis],
            key_steps: result[:key_steps],
            excel_functions: result[:excel_functions],
            difficulty_level: result[:difficulty_level],
            credits_used: result[:credits_used],
            processing_time: result[:processing_time],
            video_duration: duration
          }
        end

      rescue StandardError => e
        Rails.logger.error("Video analysis failed: #{e.message}")
        render_error("비디오 분석 중 오류가 발생했습니다: #{e.message}", :internal_server_error)
      end
    end

    # 컨텍스트 포함 종합 분석
    def analyze_with_context
      return render_error("이미지, 텍스트, 컨텍스트가 필요합니다", :bad_request) unless valid_context_request?

      begin
        gemini_service = AiIntegration::Services::GeminiMultimodalService.new

        # 관련 Excel 파일 정보 포함
        enhanced_context = build_enhanced_context

        result = gemini_service.analyze_image_with_context(
          image_data: extract_image_data,
          text_prompt: params[:prompt],
          user: current_user,
          context: enhanced_context
        )

        if result[:analysis]
          # 컨텍스트 기반 후처리
          enhanced_result = enhance_result_with_context(result, enhanced_context)

          # 사용량 추적
          track_contextual_usage(enhanced_result)

          render json: {
            success: true,
            analysis: enhanced_result[:analysis],
            contextual_insights: enhanced_result[:contextual_insights],
            related_files: enhanced_result[:related_files],
            confidence_score: enhanced_result[:confidence_score],
            credits_used: enhanced_result[:credits_used],
            provider: enhanced_result[:provider],
            processing_time: enhanced_result[:processing_time]
          }
        else
          render_error("컨텍스트 분석에 실패했습니다", :unprocessable_entity)
        end

      rescue StandardError => e
        Rails.logger.error("Contextual analysis failed: #{e.message}")
        render_error("컨텍스트 분석 중 오류가 발생했습니다: #{e.message}", :internal_server_error)
      end
    end

    private

    def valid_image_request?
      params[:image].present? && params[:prompt].present?
    end

    def valid_video_request?
      params[:video].present?
    end

    def valid_context_request?
      params[:image].present? && params[:prompt].present? && params[:context].present?
    end

    def extract_image_data
      if params[:image].respond_to?(:read)
        params[:image].read
      elsif params[:image].is_a?(String) && params[:image].start_with?("data:")
        # Data URL에서 Base64 데이터 추출
        base64_data = params[:image].split(",")[1]
        Base64.decode64(base64_data)
      elsif params[:image].is_a?(String)
        # 순수 Base64 데이터
        Base64.decode64(params[:image])
      else
        params[:image]
      end
    end

    def extract_video_data
      if params[:video].respond_to?(:read)
        params[:video].read
      elsif params[:video].is_a?(String)
        Base64.decode64(params[:video])
      else
        params[:video]
      end
    end

    def extract_video_duration
      params[:duration]&.to_i || estimate_video_duration
    end

    def estimate_video_duration
      # 비디오 데이터에서 길이 추정 (간소화)
      video_size = extract_video_data.bytesize
      # 대략적 추정: 1MB당 30초
      (video_size / 1.megabyte * 30).to_i
    end

    def build_analysis_context
      {
        analysis_type: params[:analysis_type] || "general",
        excel_context: params[:excel_context],
        user_intent: params[:user_intent],
        file_context: params[:file_context]
      }
    end

    def build_enhanced_context
      context = build_analysis_context

      # 사용자의 최근 Excel 파일들 정보 추가
      recent_files = current_user.excel_files
                                .order(created_at: :desc)
                                .limit(5)
                                .pluck(:original_name, :created_at)

      context[:recent_files] = recent_files
      context[:user_tier] = current_user.tier
      context[:analysis_history] = get_recent_analysis_themes

      context
    end

    def get_recent_analysis_themes
      # 사용자의 최근 분석 테마들 (간소화)
      current_user.analyses
                  .joins(:excel_file)
                  .where(created_at: 1.week.ago..Time.current)
                  .limit(10)
                  .pluck("excel_files.original_name")
                  .map { |name| extract_theme_from_filename(name) }
                  .uniq
    end

    def extract_theme_from_filename(filename)
      case filename.downcase
      when /budget|예산|재무/ then "financial"
      when /inventory|재고|stock/ then "inventory"
      when /sales|판매|매출/ then "sales"
      when /project|프로젝트|일정/ then "project"
      when /hr|인사|직원/ then "hr"
      else "general"
      end
    end

    def enhance_result_with_context(result, context)
      enhanced = result.dup

      # 컨텍스트 기반 추가 인사이트
      enhanced[:contextual_insights] = generate_contextual_insights(result, context)

      # 관련 파일 추천
      enhanced[:related_files] = suggest_related_files(context)

      # 사용자 히스토리 기반 개인화
      enhanced[:personalized_suggestions] = generate_personalized_suggestions(context)

      enhanced
    end

    def generate_contextual_insights(result, context)
      insights = []

      # 분석 결과와 사용자 히스토리 매칭
      if context[:analysis_history]&.include?("financial") && result[:analysis].include?("budget")
        insights << "이전 재무 분석 경험을 바탕으로, 예산 계획 개선 방안을 제안드립니다."
      end

      # 사용자 티어별 맞춤 제안
      case context[:user_tier]
      when "enterprise"
        insights << "엔터프라이즈 사용자를 위한 고급 분석 기능을 활용해보세요."
      when "pro"
        insights << "Pro 사용자 전용 최적화 기능으로 더 정확한 분석이 가능합니다."
      end

      insights
    end

    def suggest_related_files(context)
      # 테마 기반 관련 파일 추천
      theme = context[:analysis_history]&.first || "general"

      current_user.excel_files
                  .joins(:analyses)
                  .where("excel_files.original_name ILIKE ?", "%#{theme}%")
                  .limit(3)
                  .map do |file|
        {
          id: file.id,
          name: file.original_name,
          last_analysis: file.analyses.last&.created_at
        }
      end
    end

    def generate_personalized_suggestions(context)
      suggestions = []

      # 사용자 패턴 기반 제안
      frequent_themes = context[:analysis_history] || []

      if frequent_themes.include?("financial")
        suggestions << "재무 분석 템플릿을 사용해 보세요"
      end

      if frequent_themes.include?("project")
        suggestions << "프로젝트 관리 기능을 활용해 보세요"
      end

      suggestions
    end

    def track_multimodal_usage(result)
      Usage.create!(
        user: current_user,
        feature: "multimodal_image_analysis",
        credits_used: result[:credits_used],
        provider: result[:provider],
        cost: calculate_cost(result[:credits_used]),
        metadata: {
          confidence_score: result[:confidence_score],
          processing_time: result[:processing_time]
        }
      )
    end

    def track_video_usage(result, duration)
      Usage.create!(
        user: current_user,
        feature: "multimodal_video_analysis",
        credits_used: result[:credits_used],
        provider: "gemini",
        cost: calculate_cost(result[:credits_used]),
        metadata: {
          video_duration: duration,
          processing_time: result[:processing_time]
        }
      )
    end

    def track_contextual_usage(result)
      Usage.create!(
        user: current_user,
        feature: "multimodal_contextual_analysis",
        credits_used: result[:credits_used],
        provider: result[:provider],
        cost: calculate_cost(result[:credits_used]),
        metadata: {
          confidence_score: result[:confidence_score],
          processing_time: result[:processing_time],
          enhanced_features: true
        }
      )
    end

    def calculate_cost(credits_used)
      # Gemini Flash 비용: $0.075 per 1M tokens
      (credits_used.to_f / 1_000_000) * 0.075
    end

    def check_user_tokens
      required_tokens = case action_name
      when "analyze_video" then 50    # 비디오 분석은 많은 토큰 소모
      when "analyze_with_context" then 30  # 컨텍스트 분석
      else 20  # 기본 이미지 분석
      end

      unless current_user.credits >= required_tokens
        render_error("토큰이 부족합니다. 이 기능을 사용하려면 #{required_tokens}토큰이 필요합니다.", :payment_required)
      end
    end

    def render_error(message, status)
      render json: {
        success: false,
        error: message
      }, status: status
    end
  end
end
