# frozen_string_literal: true

module Api
  module V1
    class AiCostMonitoringController < ApplicationController
      before_action :authenticate_api_user!

      # GET /api/v1/ai_cost_monitoring/balance
      def balance
        balance_data = fetch_balance_data

        render json: balance_data
      end

      # GET /api/v1/ai_cost_monitoring/usage
      def usage
        days = params[:days]&.to_i || 7
        usage_data = fetch_usage_data(days)

        render json: usage_data
      end

      # GET /api/v1/ai_cost_monitoring/models
      def models
        models_data = fetch_available_models

        render json: models_data
      end

      private

      def fetch_balance_data
        # Get current AI usage and balance information
        ai_usage = calculate_current_ai_usage

        {
          balance: calculate_remaining_balance,
          usage: ai_usage[:total_cost],
          limit: get_monthly_limit,
          is_free_tier: is_free_tier_account?,
          rate_limit: get_rate_limit_info,
          last_updated: Time.current.iso8601
        }
      end

      def fetch_usage_data(days)
        # Fetch usage data for the specified number of days
        end_date = Date.current
        start_date = end_date - days.days

        # Get usage from database (assuming we have usage tracking)
        usage_records = fetch_usage_records(start_date, end_date)

        {
          period: {
            start: start_date.iso8601,
            end: end_date.iso8601,
            days: days
          },
          total_cost: usage_records.sum { |r| r[:cost] },
          total_requests: usage_records.sum { |r| r[:requests] },
          models_used: group_usage_by_model(usage_records),
          daily_usage: build_daily_usage(usage_records, start_date, end_date),
          top_models: build_top_models(usage_records),
          currentSession: build_current_session_stats,
          modelUsage: build_model_usage_stats,
          monthly: build_monthly_stats,
          dailyStats: build_daily_stats,
          accountInfo: build_account_info
        }
      end

      def fetch_available_models
        # Return available AI models with pricing
        models = [
          {
            id: "openai/gpt-4o-mini",
            name: "GPT-4o Mini",
            category: "OpenAI",
            pricing: {
              prompt: "0.00015",
              completion: "0.0006"
            },
            context_length: 128000,
            is_popular: true,
            description: "Fast, affordable model for simple tasks"
          },
          {
            id: "openai/gpt-4o",
            name: "GPT-4o",
            category: "OpenAI",
            pricing: {
              prompt: "0.005",
              completion: "0.015"
            },
            context_length: 128000,
            is_popular: true,
            description: "Most capable OpenAI model"
          },
          {
            id: "anthropic/claude-3.5-sonnet",
            name: "Claude 3.5 Sonnet",
            category: "Anthropic",
            pricing: {
              prompt: "0.003",
              completion: "0.015"
            },
            context_length: 200000,
            is_popular: true,
            description: "Balanced performance and cost"
          },
          {
            id: "anthropic/claude-3-haiku",
            name: "Claude 3 Haiku",
            category: "Anthropic",
            pricing: {
              prompt: "0.00025",
              completion: "0.00125"
            },
            context_length: 200000,
            is_popular: false,
            description: "Fast and economical model"
          },
          {
            id: "google/gemini-flash-1.5",
            name: "Gemini Flash 1.5",
            category: "Google",
            pricing: {
              prompt: "0.000075",
              completion: "0.0003"
            },
            context_length: 1000000,
            is_popular: false,
            description: "Ultra-fast model with large context"
          }
        ]

        models
      end

      def calculate_current_ai_usage
        # Calculate current AI usage from the database
        current_month_usage = AiUsageRecord.this_month

        {
          total_cost: current_month_usage.sum(:cost),
          total_requests: current_month_usage.count,
          total_tokens: current_month_usage.sum(:input_tokens) + current_month_usage.sum(:output_tokens),
          input_tokens: current_month_usage.sum(:input_tokens),
          output_tokens: current_month_usage.sum(:output_tokens)
        }
      end

      def calculate_remaining_balance
        # Calculate remaining balance based on usage
        limit = get_monthly_limit
        usage = calculate_current_ai_usage

        limit - usage[:total_cost]
      end

      def get_monthly_limit
        # Return monthly spending limit
        # This could be user-specific or system-wide
        25.0 # $25 default limit
      end

      def is_free_tier_account?
        # Check if user is on free tier
        # This would be based on user's subscription status
        true # Default to free tier
      end

      def get_rate_limit_info
        # Return rate limit information
        {
          requests_per_minute: 100,
          tokens_per_minute: 10000,
          requests_per_day: 1000
        }
      end

      def fetch_usage_records(start_date, end_date)
        # Fetch usage records from database
        usage_records = AiUsageRecord.by_date_range(start_date, end_date)

        # Convert to the format expected by the API
        usage_records.map do |record|
          {
            date: record.created_at.to_date,
            cost: record.cost,
            requests: 1, # Each record represents one request
            tokens: record.input_tokens + record.output_tokens,
            model: record.model_id,
            provider: record.provider,
            input_tokens: record.input_tokens,
            output_tokens: record.output_tokens,
            request_type: record.request_type
          }
        end
      end

      def group_usage_by_model(usage_records)
        usage_records.group_by { |r| r[:model] }
                    .transform_values do |records|
                      {
                        cost: records.sum { |r| r[:cost] },
                        requests: records.sum { |r| r[:requests] },
                        tokens: records.sum { |r| r[:credits] }
                      }
                    end
      end

      def build_daily_usage(usage_records, start_date, end_date)
        daily_usage = {}

        # Initialize all dates with zero usage
        (start_date..end_date).each do |date|
          daily_usage[date] = { cost: 0, requests: 0, tokens: 0 }
        end

        # Fill in actual usage
        usage_records.each do |record|
          date = record[:date]
          daily_usage[date][:cost] += record[:cost]
          daily_usage[date][:requests] += record[:requests]
          daily_usage[date][:credits] += record[:credits]
        end

        daily_usage.map do |date, stats|
          {
            date: date.strftime("%Y-%m-%d"),
            cost: stats[:cost].round(4),
            requests: stats[:requests]
          }
        end
      end

      def build_top_models(usage_records)
        model_usage = group_usage_by_model(usage_records)

        model_usage.map do |model, stats|
          {
            model: model,
            cost: stats[:cost].round(4),
            requests: stats[:requests]
          }
        end.sort_by { |model| -model[:cost] }.first(5)
      end

      def build_current_session_stats
        # Build current session statistics
        {
          totalCost: 0.0,
          totalRequests: 0,
          totalTokens: 0,
          inputTokens: 0,
          outputTokens: 0,
          activeModels: 0,
          primaryModel: "anthropic/claude-3.5-sonnet",
          lastUsed: Time.current.strftime("%H:%M:%S"),
          requestsPerMinute: 0
        }
      end

      def build_model_usage_stats
        # Build model usage statistics
        models = fetch_available_models

        models.first(3).map do |model|
          {
            model: model[:id],
            cost: 0.0,
            requests: 0,
            inputTokens: 0,
            outputTokens: 0,
            lastUsed: Time.current.strftime("%H:%M:%S"),
            isActive: false,
            efficiencyScore: 0,
            usageTrend: [],
            tier: determine_model_tier(model[:id])
          }
        end
      end

      def build_monthly_stats
        current_usage = calculate_current_ai_usage

        {
          total_cost: current_usage[:total_cost],
          total_requests: current_usage[:total_requests],
          total_tokens: current_usage[:total_tokens]
        }
      end

      def build_daily_stats
        current_usage = calculate_current_ai_usage

        {
          today: current_usage[:total_cost],
          yesterday: 0,
          thisWeek: current_usage[:total_cost],
          thisMonth: current_usage[:total_cost]
        }
      end

      def build_account_info
        {
          isFreeTier: is_free_tier_account?,
          limit: get_monthly_limit,
          limitRemaining: calculate_remaining_balance,
          rateLimit: get_rate_limit_info
        }
      end

      def determine_model_tier(model_id)
        if model_id.include?("haiku") || model_id.include?("gpt-4o-mini") || model_id.include?("gemini-flash")
          "budget"
        elsif model_id.include?("sonnet") || model_id.include?("gpt-4o")
          "balanced"
        else
          "premium"
        end
      end

      def authenticate_api_user!
        # For now, allow all requests
        # In production, implement proper API authentication
        true
      end
    end
  end
end
