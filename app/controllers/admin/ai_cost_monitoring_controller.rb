# frozen_string_literal: true

class Admin::AiCostMonitoringController < ApplicationController
  before_action :authenticate_admin!

  def index
    @time_range = params[:time_range] || "today"
    @user_filter = params[:user_id].present? ? User.find(params[:user_id]) : nil

    handler = AiCostMonitoring::Handlers::CostMonitoringHandler.new(
      user: @user_filter,
      time_range: @time_range
    )

    result = handler.execute

    if result.success?
      @cost_data = result.value
    else
      @cost_data = default_cost_data
      flash.now[:alert] = "비용 모니터링 데이터를 불러오는 중 오류가 발생했습니다."
    end
  end

  def api_usage
    render json: get_api_usage_data
  end

  def model_comparison
    render json: get_model_comparison_data
  end

  def cost_breakdown
    render json: get_cost_breakdown_data
  end

  private

  def authenticate_admin!
    redirect_to login_path unless current_user&.admin?
  end

  def default_cost_data
    {
      overview: {
        total_cost: 0.0,
        today_cost: 0.0,
        remaining_budget: 100.0,
        monthly_budget: 100.0
      },
      usage_by_model: [],
      usage_by_tier: [],
      daily_usage: {},
      cost_trends: {
        daily_change: 0,
        weekly_change: 0,
        monthly_change: 0,
        growth_rate: 0
      },
      token_usage: {
        total_tokens: 0,
        today_tokens: 0,
        avg_tokens_per_request: 0,
        token_efficiency: 0
      },
      predictions: {
        monthly_projection: 0,
        budget_depletion_date: nil,
        recommended_budget: 100.0
      }
    }
  end

  def get_api_usage_data
    time_range = params[:time_range] || "week"

    # Get API usage data by provider
    usage_data = {}

    case time_range
    when "today"
      usage_data = get_today_api_usage
    when "week"
      usage_data = get_week_api_usage
    when "month"
      usage_data = get_month_api_usage
    end

    {
      timeRange: time_range,
      usage: usage_data,
      totalRequests: usage_data.values.sum,
      avgLatency: calculate_avg_latency,
      errorRate: calculate_error_rate
    }
  end

  def get_today_api_usage
    # Mock data - replace with actual API usage tracking
    {
      "OpenAI" => rand(50..200),
      "Anthropic" => rand(100..300),
      "Google" => rand(20..80)
    }
  end

  def get_week_api_usage
    # Mock data for weekly usage
    {
      "OpenAI" => rand(300..1000),
      "Anthropic" => rand(500..1500),
      "Google" => rand(100..400)
    }
  end

  def get_month_api_usage
    # Mock data for monthly usage
    {
      "OpenAI" => rand(1000..4000),
      "Anthropic" => rand(2000..6000),
      "Google" => rand(500..2000)
    }
  end

  def calculate_avg_latency
    # Mock average latency in milliseconds
    rand(800..1500)
  end

  def calculate_error_rate
    # Mock error rate as percentage
    rand(0.1..2.5).round(2)
  end

  def get_model_comparison_data
    models = [
      "claude-3-haiku-20240307",
      "claude-3-sonnet-20240229",
      "claude-3-opus-20240229",
      "gpt-4o-mini",
      "gpt-4o"
    ]

    comparison_data = models.map do |model|
      {
        model: model,
        cost_per_1k_tokens: get_model_cost_per_1k_tokens(model),
        avg_response_time: rand(500..2000),
        quality_score: rand(7.5..9.5).round(2),
        usage_count: rand(10..500)
      }
    end

    {
      models: comparison_data,
      recommendations: get_model_recommendations(comparison_data)
    }
  end

  def get_model_cost_per_1k_tokens(model)
    # Actual pricing data (approximate)
    case model
    when "claude-3-haiku-20240307"
      0.0025
    when "claude-3-sonnet-20240229"
      0.015
    when "claude-3-opus-20240229"
      0.075
    when "gpt-4o-mini"
      0.0015
    when "gpt-4o"
      0.030
    else
      0.010
    end
  end

  def get_model_recommendations(comparison_data)
    [
      {
        type: "cost_efficient",
        model: comparison_data.min_by { |m| m[:cost_per_1k_tokens] }[:model],
        reason: "가장 비용 효율적인 모델입니다."
      },
      {
        type: "best_quality",
        model: comparison_data.max_by { |m| m[:quality_score] }[:model],
        reason: "가장 높은 품질의 응답을 제공합니다."
      },
      {
        type: "balanced",
        model: comparison_data.max_by { |m| m[:quality_score] / m[:cost_per_1k_tokens] }[:model],
        reason: "품질과 비용의 균형이 가장 좋습니다."
      }
    ]
  end

  def get_cost_breakdown_data
    {
      by_feature: {
        "Excel 분석" => rand(40..60),
        "AI 채팅" => rand(20..35),
        "RAG 검색" => rand(10..25),
        "기타" => rand(5..15)
      },
      by_user_tier: {
        "Free" => rand(10..20),
        "Pro" => rand(50..70),
        "Enterprise" => rand(20..40)
      },
      by_time_of_day: generate_hourly_usage_data
    }
  end

  def generate_hourly_usage_data
    hourly_data = {}

    24.times do |hour|
      # Simulate higher usage during business hours
      multiplier = if hour.between?(9, 17)
        rand(0.8..1.2)
      elsif hour.between?(18, 22)
        rand(0.4..0.8)
      else
        rand(0.1..0.4)
      end

      hourly_data[hour.to_s.rjust(2, "0")] = (rand(10..50) * multiplier).round(2)
    end

    hourly_data
  end
end
