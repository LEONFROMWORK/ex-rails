# frozen_string_literal: true

module UserManagement
  module Handlers
    class UserProfileHandler < Common::BaseHandler
      def initialize(user:, params: {})
        @user = user
        @params = params
      end

      def execute
        case @params[:action]
        when "show"
          get_user_profile
        when "update"
          update_user_profile
        when "usage_stats"
          get_usage_statistics
        else
          get_user_profile
        end
      end

      private

      def get_user_profile
        begin
          profile_data = {
            user: serialize_user,
            subscription: serialize_subscription,
            usage_summary: get_usage_summary,
            recent_activity: get_recent_activity
          }

          Rails.logger.info("User profile retrieved for user #{@user.id}")

          Common::Result.success(profile_data)
        rescue StandardError => e
          Rails.logger.error("Failed to retrieve user profile: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to retrieve user profile",
              code: "PROFILE_RETRIEVAL_ERROR"
            )
          )
        end
      end

      def update_user_profile
        begin
          update_params = @params.except(:action)

          # Validate allowed fields
          allowed_fields = [ :name, :email, :notification_preferences ]
          filtered_params = update_params.slice(*allowed_fields)

          if filtered_params.empty?
            return Common::Result.failure(
              Common::Errors::ValidationError.new(
                message: "No valid fields provided for update"
              )
            )
          end

          # Update user
          @user.update!(filtered_params)

          Rails.logger.info("User profile updated for user #{@user.id}")

          Common::Result.success({
            user: serialize_user,
            message: "Profile updated successfully"
          })
        rescue ActiveRecord::RecordInvalid => e
          Common::Result.failure(
            Common::Errors::ValidationError.new(
              message: "Profile update failed: #{e.message}"
            )
          )
        rescue StandardError => e
          Rails.logger.error("Failed to update user profile: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to update user profile",
              code: "PROFILE_UPDATE_ERROR"
            )
          )
        end
      end

      def get_usage_statistics
        begin
          usage_stats = {
            token_usage: calculate_token_usage,
            file_analysis: calculate_file_analysis_stats,
            ai_usage: calculate_ai_usage_stats,
            payment_history: calculate_payment_stats
          }

          Rails.logger.info("Usage statistics retrieved for user #{@user.id}")

          Common::Result.success(usage_stats)
        rescue StandardError => e
          Rails.logger.error("Failed to retrieve usage statistics: #{e.message}")
          Common::Result.failure(
            Common::Errors::BusinessError.new(
              message: "Failed to retrieve usage statistics",
              code: "USAGE_STATS_ERROR"
            )
          )
        end
      end

      def serialize_user
        {
          id: @user.id,
          name: @user.name,
          email: @user.email,
          tier: @user.tier,
          role: @user.role,
          tokens: @user.credits,
          email_verified: @user.email_verified,
          created_at: @user.created_at,
          last_login: @user.updated_at, # Assuming this tracks login
          referral_code: @user.referral_code
        }
      end

      def serialize_subscription
        subscription = @user.subscription
        return nil unless subscription

        {
          id: subscription.id,
          tier: subscription.tier,
          status: subscription.status,
          current_period_start: subscription.current_period_start,
          current_period_end: subscription.current_period_end,
          auto_renew: subscription.auto_renew,
          canceled_at: subscription.canceled_at
        }
      end

      def get_usage_summary
        {
          total_files_uploaded: @user.excel_files.count,
          total_analyses_completed: @user.analyses.count,
          total_spent: @user.total_spent,
          credits_used_this_month: calculate_credits_used_this_month,
          ai_requests_this_month: calculate_ai_requests_this_month
        }
      end

      def get_recent_activity
        {
          recent_files: @user.excel_files.recent.limit(5).pluck(:original_name, :created_at),
          recent_analyses: @user.analyses.recent.limit(5).includes(:excel_file)
                               .map { |a| { file_name: a.excel_file.original_name, created_at: a.created_at } },
          recent_payments: @user.payments.recent.limit(3)
                                .map { |p| { amount: p.amount, type: p.payment_intent.payment_type, created_at: p.created_at } }
        }
      end

      def calculate_token_usage
        {
          current_balance: @user.credits,
          total_purchased: calculate_total_tokens_purchased,
          total_used: calculate_total_credits_used,
          usage_this_month: calculate_credits_used_this_month,
          projected_monthly_usage: calculate_projected_monthly_usage
        }
      end

      def calculate_file_analysis_stats
        {
          total_files: @user.excel_files.count,
          files_this_month: @user.excel_files.where(created_at: 1.month.ago..Time.current).count,
          successful_analyses: @user.analyses.where.not(ai_analysis: nil).count,
          failed_analyses: @user.excel_files.where(status: "failed").count,
          avg_file_size: @user.excel_files.average(:file_size).to_f / 1.megabyte
        }
      end

      def calculate_ai_usage_stats
        {
          total_ai_requests: @user.analyses.count,
          tier1_requests: @user.analyses.where(ai_tier_used: "tier1").count,
          tier2_requests: @user.analyses.where(ai_tier_used: "tier2").count,
          total_tokens_consumed: @user.analyses.sum(:credits_used),
          avg_tokens_per_request: @user.analyses.average(:credits_used).to_f.round(2)
        }
      end

      def calculate_payment_stats
        {
          total_payments: @user.payments.count,
          total_amount_paid: @user.total_spent,
          avg_payment_amount: @user.payments.average(:amount).to_f.round(2),
          last_payment_date: @user.payments.recent.first&.created_at,
          preferred_payment_method: @user.payments.group(:payment_method).count.max_by { |_, count| count }&.first
        }
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

      def calculate_ai_requests_this_month
        @user.analyses.where(created_at: 1.month.ago..Time.current).count
      end

      def calculate_projected_monthly_usage
        # Simple projection based on current month usage
        current_month_usage = calculate_credits_used_this_month
        days_passed = Time.current.day
        days_in_month = Time.current.end_of_month.day

        return 0 if days_passed == 0

        (current_month_usage.to_f / days_passed * days_in_month).round
      end
    end
  end
end
