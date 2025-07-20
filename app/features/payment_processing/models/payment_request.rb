# frozen_string_literal: true

module PaymentProcessing
  module Models
    class PaymentRequest
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :user
      attribute :amount, :integer
      attribute :payment_type, :string
      attribute :currency, :string, default: "KRW"

      validates :user, presence: true
      validates :amount, presence: true, numericality: { greater_than: 0 }
      validates :payment_type, presence: true, inclusion: { in: %w[token_purchase subscription] }
      validates :currency, presence: true, inclusion: { in: %w[KRW USD] }

      def valid_for_user?
        return false unless user.present?

        case payment_type
        when "token_purchase"
          # Anyone can purchase tokens
          true
        when "subscription"
          # Check if user can upgrade/change subscription
          can_change_subscription?
        else
          false
        end
      end

      def minimum_amount
        case payment_type
        when "token_purchase"
          1000 # 1000 KRW minimum for token purchase
        when "subscription"
          9900 # 9900 KRW minimum for basic subscription
        else
          0
        end
      end

      def maximum_amount
        case payment_type
        when "token_purchase"
          1_000_000 # 1M KRW maximum for single token purchase
        when "subscription"
          100_000 # 100K KRW maximum for enterprise subscription
        else
          0
        end
      end

      def token_amount
        return 0 unless payment_type == "token_purchase"

        # 100 KRW = 1 token
        (amount / 100).to_i
      end

      def subscription_tier
        return nil unless payment_type == "subscription"

        case amount
        when 0..9_899
          nil # Invalid amount
        when 9_900..29_899
          "pro"
        when 29_900..Float::INFINITY
          "enterprise"
        else
          nil
        end
      end

      private

      def can_change_subscription?
        # Users can always upgrade or start a subscription
        # Add more complex logic here if needed (e.g., cooldown periods)
        true
      end
    end

    class PaymentConfirmationRequest
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :order_id, :string
      attribute :payment_key, :string
      attribute :amount, :integer

      validates :order_id, presence: true
      validates :payment_key, presence: true
      validates :amount, presence: true, numericality: { greater_than: 0 }
    end

    class WebhookRequest
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :payload, :string
      attribute :signature, :string

      validates :payload, presence: true
      validates :signature, presence: true
    end
  end
end
