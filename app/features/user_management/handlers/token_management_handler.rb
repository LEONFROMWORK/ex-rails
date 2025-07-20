# frozen_string_literal: true

module UserManagement
  module Handlers
    class TokenManagementHandler < Common::BaseHandler
      def initialize(user:, action:, params: {})
        @user = user
        @action = action
        @params = params
      end

      def execute
        case @action
        when "balance"
          get_token_balance
        when "history"
          get_token_history
        when "usage_forecast"
          get_usage_forecast
        else
          Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "Invalid action: #{@action}"
            )
          )
        end
      end

      private

      def get_token_balance
        begin
          balance_data = {
            current_balance: @user.credits,
            pending_purchases: calculate_pending_purchases,
            reserved_tokens: calculate_reserved_tokens,
            available_tokens: calculate_available_tokens,
            low_balance_warning: @user.credits < 10
          }

          Rails.logger.info("Token balance retrieved for user #{@user.id}")

          Common::Result.success(balance_data)
        rescue StandardError => e
          Rails.logger.error("Failed to retrieve token balance: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to retrieve token balance",
              code: "TOKEN_BALANCE_ERROR"
            )
          )
        end
      end

      def get_token_history
        begin
          history_data = {
            transactions: get_token_transactions,
            usage_summary: get_token_usage_summary,
            monthly_breakdown: get_monthly_token_breakdown
          }

          Rails.logger.info("Token history retrieved for user #{@user.id}")

          Common::Result.success(history_data)
        rescue StandardError => e
          Rails.logger.error("Failed to retrieve token history: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to retrieve token history",
              code: "TOKEN_HISTORY_ERROR"
            )
          )
        end
      end

      def get_usage_forecast
        begin
          forecast_data = {
            daily_average: calculate_daily_average_usage,
            weekly_forecast: calculate_weekly_forecast,
            monthly_forecast: calculate_monthly_forecast,
            recommendations: generate_usage_recommendations
          }

          Rails.logger.info("Usage forecast generated for user #{@user.id}")

          Common::Result.success(forecast_data)
        rescue StandardError => e
          Rails.logger.error("Failed to generate usage forecast: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to generate usage forecast",
              code: "USAGE_FORECAST_ERROR"
            )
          )
        end
      end

      def calculate_pending_purchases
        @user.payment_intents.where(payment_type: "token_purchase", status: "pending")
             .sum { |pi| pi.token_amount }
      end

      def calculate_reserved_tokens
        # Tokens reserved for ongoing analyses
        @user.excel_files.where(status: "processing").count * 10
      end

      def calculate_available_tokens
        @user.credits - calculate_reserved_tokens
      end

      def get_token_transactions
        transactions = []

        # Token purchases
        @user.payment_intents.where(payment_type: "token_purchase", status: "completed")
             .recent.limit(20).each do |pi|
          transactions << {
            type: "purchase",
            amount: pi.token_amount,
            date: pi.paid_at,
            description: "Token purchase - #{pi.token_amount} tokens",
            reference: pi.order_id
          }
        end

        # Token usage
        @user.analyses.recent.limit(20).each do |analysis|
          transactions << {
            type: "usage",
            amount: -analysis.credits_used,
            date: analysis.created_at,
            description: "AI analysis - #{analysis.excel_file.original_name}",
            reference: analysis.id
          }
        end

        transactions.sort_by { |t| t[:date] }.reverse
      end

      def get_token_usage_summary
        {
          total_purchased: calculate_total_tokens_purchased,
          total_used: calculate_total_credits_used,
          usage_this_month: calculate_credits_used_this_month,
          most_expensive_analysis: find_most_expensive_analysis,
          usage_by_tier: calculate_usage_by_tier
        }
      end

      def get_monthly_token_breakdown
        months = 6.times.map { |i| i.months.ago.beginning_of_month }

        months.map do |month|
          start_date = month
          end_date = month.end_of_month

          purchased = @user.payment_intents.where(
            payment_type: "token_purchase",
            status: "completed",
            paid_at: start_date..end_date
          ).sum { |pi| pi.token_amount }

          used = @user.analyses.where(created_at: start_date..end_date).sum(:credits_used)

          {
            month: month.strftime("%Y-%m"),
            purchased: purchased,
            used: used,
            net_change: purchased - used
          }
        end.reverse
      end

      def calculate_daily_average_usage
        days_with_usage = @user.analyses.where(created_at: 30.days.ago..Time.current)
                               .group_by { |a| a.created_at.to_date }
                               .count

        return 0 if days_with_usage == 0

        total_usage = calculate_credits_used_this_month
        (total_usage.to_f / [ days_with_usage, 1 ].max).round(2)
      end

      def calculate_weekly_forecast
        daily_average = calculate_daily_average_usage
        weekly_forecast = daily_average * 7

        {
          estimated_usage: weekly_forecast.round,
          confidence: calculate_forecast_confidence,
          sufficient_balance: @user.credits >= weekly_forecast
        }
      end

      def calculate_monthly_forecast
        daily_average = calculate_daily_average_usage
        monthly_forecast = daily_average * 30

        {
          estimated_usage: monthly_forecast.round,
          confidence: calculate_forecast_confidence,
          sufficient_balance: @user.credits >= monthly_forecast,
          recommended_purchase: calculate_recommended_purchase(monthly_forecast)
        }
      end

      def generate_usage_recommendations
        recommendations = []

        # Low balance warning
        if @user.credits < 10
          recommendations << {
            type: "low_balance",
            message: "Your token balance is low. Consider purchasing more tokens.",
            action: "purchase_tokens"
          }
        end

        # High usage warning
        monthly_usage = calculate_credits_used_this_month
        if monthly_usage > 100
          recommendations << {
            type: "high_usage",
            message: "Your monthly usage is high. Consider upgrading to a higher tier.",
            action: "upgrade_subscription"
          }
        end

        # Unused tokens
        if @user.credits > 200 && calculate_daily_average_usage < 5
          recommendations << {
            type: "unused_tokens",
            message: "You have many unused tokens. Consider using our AI chat feature.",
            action: "explore_features"
          }
        end

        recommendations
      end

      def calculate_forecast_confidence
        # Simple confidence calculation based on usage consistency
        recent_usage = @user.analyses.where(created_at: 7.days.ago..Time.current).count
        return 0.3 if recent_usage < 3

        0.8 # High confidence if user has recent activity
      end

      def calculate_recommended_purchase(monthly_forecast)
        return 0 if @user.credits >= monthly_forecast

        deficit = monthly_forecast - @user.credits
        # Round up to nearest 50 tokens
        ((deficit / 50.0).ceil * 50).to_i
      end

      def calculate_total_tokens_purchased
        @user.payment_intents.where(payment_type: "token_purchase", status: "completed")
             .sum { |pi| pi.token_amount }
      end

      def calculate_total_credits_used
        @user.analyses.sum(:credits_used) || 0
      end

      def calculate_credits_used_this_month
        @user.analyses.where(created_at: 1.month.ago..Time.current).sum(:credits_used) || 0
      end

      def find_most_expensive_analysis
        analysis = @user.analyses.order(credits_used: :desc).first
        return nil unless analysis

        {
          file_name: analysis.excel_file.original_name,
          credits_used: analysis.credits_used,
          date: analysis.created_at,
          tier: analysis.ai_tier_used
        }
      end

      def calculate_usage_by_tier
        {
          tier1: @user.analyses.where(ai_tier_used: "tier1").sum(:credits_used),
          tier2: @user.analyses.where(ai_tier_used: "tier2").sum(:credits_used)
        }
      end
    end
  end
end
