# frozen_string_literal: true

module PaymentProcessing
  module Handlers
    class PaymentHandler < Common::BaseHandler
      def initialize
        @toss_service = Services::TossPaymentsService.new
      end

      def create_payment(request)
        # Validate request
        validation_result = validate_payment_request(request)
        return validation_result if validation_result.failure?

        user = request.user
        amount = request.amount
        payment_type = request.payment_type

        # Create payment intent
        payment_intent = create_payment_intent(user, amount, payment_type)
        return payment_intent if payment_intent.failure?

        # Initiate TossPayments payment
        toss_result = @toss_service.create_payment(
          amount: amount,
          order_id: payment_intent.value.order_id,
          customer_email: user.email,
          customer_name: user.name,
          payment_type: payment_type
        )

        if toss_result.success?
          # Update payment intent with TossPayments data
          payment_intent.value.update!(
            toss_payment_key: toss_result.value[:payment_key],
            status: "pending"
          )

          Common::Result.success({
            payment_url: toss_result.value[:checkout_url],
            order_id: payment_intent.value.order_id,
            amount: amount
          })
        else
          payment_intent.value.update!(status: "failed", error_message: toss_result.error.message)
          toss_result
        end

      rescue StandardError => e
        Rails.logger.error("Payment creation failed: #{e.message}")
        Common::Result.failure(
          Common::Errors::BusinessError.new(
            message: "Payment processing failed: #{e.message}",
            code: "PAYMENT_ERROR"
          )
        )
      end

      def confirm_payment(request)
        # Validate confirmation request
        validation_result = validate_confirmation_request(request)
        return validation_result if validation_result.failure?

        order_id = request.order_id
        payment_key = request.payment_key

        # Find payment intent
        payment_intent = find_payment_intent(order_id)
        return payment_intent if payment_intent.failure?

        # Confirm with TossPayments
        toss_result = @toss_service.confirm_payment(
          payment_key: payment_key,
          order_id: order_id,
          amount: payment_intent.value.amount
        )

        if toss_result.success?
          # Process successful payment
          process_successful_payment(payment_intent.value, toss_result.value)
        else
          # Handle payment failure
          payment_intent.value.update!(
            status: "failed",
            error_message: toss_result.error.message
          )
          toss_result
        end

      rescue StandardError => e
        Rails.logger.error("Payment confirmation failed: #{e.message}")
        Common::Result.failure(
          Common::Errors::BusinessError.new(
            message: "Payment confirmation failed: #{e.message}",
            code: "PAYMENT_CONFIRMATION_ERROR"
          )
        )
      end

      def handle_webhook(request)
        # Validate webhook signature
        signature_valid = @toss_service.verify_webhook_signature(
          request.payload,
          request.signature
        )

        unless signature_valid
          Rails.logger.warn("Invalid TossPayments webhook signature")
          return Common::Result.failure("Invalid webhook signature")
        end

        event_data = JSON.parse(request.payload)
        event_type = event_data["eventType"]
        payment_data = event_data["data"]

        case event_type
        when "Payment.Paid"
          handle_payment_paid(payment_data)
        when "Payment.Failed"
          handle_payment_failed(payment_data)
        when "Payment.Canceled"
          handle_payment_canceled(payment_data)
        else
          Rails.logger.info("Unhandled webhook event: #{event_type}")
          Common::Result.success("Event acknowledged")
        end

      rescue JSON::ParserError => e
        Rails.logger.error("Invalid webhook payload: #{e.message}")
        Common::Result.failure("Invalid webhook payload")
      rescue StandardError => e
        Rails.logger.error("Webhook processing failed: #{e.message}")
        Common::Result.failure("Webhook processing failed")
      end

      private

      def validate_payment_request(request)
        errors = []

        errors << "User is required" unless request.user.present?
        errors << "Amount must be positive" unless request.amount.to_i > 0
        errors << "Payment type is required" unless request.payment_type.present?

        valid_types = [ "credits_purchase", "subscription" ]
        errors << "Invalid payment type" unless valid_types.include?(request.payment_type)

        return Common::Result.success if errors.empty?
        Common::Result.failure(
          Common::Errors::ValidationError.new(
            message: "Payment request validation failed",
            details: { errors: errors }
          )
        )
      end

      def validate_confirmation_request(request)
        errors = []

        errors << "Order ID is required" unless request.order_id.present?
        errors << "Payment key is required" unless request.payment_key.present?

        return Common::Result.success if errors.empty?
        Common::Result.failure(
          Common::Errors::ValidationError.new(
            message: "Payment confirmation validation failed",
            details: { errors: errors }
          )
        )
      end

      def create_payment_intent(user, amount, payment_type)
        order_id = generate_order_id

        payment_intent = PaymentIntent.create!(
          user: user,
          order_id: order_id,
          amount: amount,
          payment_type: payment_type,
          status: "created"
        )

        Common::Result.success(payment_intent)
      rescue ActiveRecord::RecordInvalid => e
        Common::Result.failure(
          Common::Errors::ValidationError.new(
            message: "Failed to create payment intent: #{e.message}"
          )
        )
      end

      def find_payment_intent(order_id)
        payment_intent = PaymentIntent.find_by(order_id: order_id)

        if payment_intent
          Common::Result.success(payment_intent)
        else
          Common::Result.failure(
            Common::Errors::NotFoundError.new(
              resource: "PaymentIntent",
              id: order_id
            )
          )
        end
      end

      def process_successful_payment(payment_intent, toss_data)
        ActiveRecord::Base.transaction do
          # Update payment intent
          payment_intent.update!(
            status: "completed",
            toss_transaction_id: toss_data["transactionKey"],
            paid_at: Time.current
          )

          # Process based on payment type
          case payment_intent.payment_type
          when "credits_purchase"
            process_credits_purchase(payment_intent)
          when "subscription"
            process_subscription_payment(payment_intent)
          end

          # Create payment record
          Payment.create!(
            user: payment_intent.user,
            payment_intent: payment_intent,
            amount: payment_intent.amount,
            payment_method: toss_data["method"],
            toss_transaction_id: toss_data["transactionKey"],
            status: "completed"
          )
        end

        Common::Result.success({
          order_id: payment_intent.order_id,
          status: "completed",
          amount: payment_intent.amount
        })
      rescue StandardError => e
        Rails.logger.error("Payment processing failed: #{e.message}")
        Common::Result.failure("Payment processing failed")
      end

      def process_credits_purchase(payment_intent)
        # Calculate credits based on amount (e.g., 1000 won = 10 credits)
        credits_purchased = (payment_intent.amount / 100).to_i

        payment_intent.user.increment!(:credits, credits_purchased)

        Rails.logger.info(
          "Added #{credits_purchased} credits to user #{payment_intent.user.id}"
        )
      end

      def process_subscription_payment(payment_intent)
        # Update or create subscription
        subscription = payment_intent.user.subscription ||
                     payment_intent.user.build_subscription

        # Determine subscription tier based on amount
        tier = determine_subscription_tier(payment_intent.amount)

        subscription.update!(
          tier: tier,
          status: "active",
          current_period_start: Time.current,
          current_period_end: 1.month.from_now
        )

        Rails.logger.info(
          "Updated subscription to #{tier} for user #{payment_intent.user.id}"
        )
      end

      def determine_subscription_tier(amount)
        case amount
        when 0..9_900
          "basic"
        when 9_900..29_900
          "pro"
        else
          "enterprise"
        end
      end

      def handle_payment_paid(payment_data)
        order_id = payment_data["orderId"]

        payment_intent = PaymentIntent.find_by(order_id: order_id)
        return Common::Result.failure("Payment intent not found") unless payment_intent

        process_successful_payment(payment_intent, payment_data)
      end

      def handle_payment_failed(payment_data)
        order_id = payment_data["orderId"]

        payment_intent = PaymentIntent.find_by(order_id: order_id)
        return Common::Result.failure("Payment intent not found") unless payment_intent

        payment_intent.update!(
          status: "failed",
          error_message: payment_data["failure"]["message"]
        )

        Common::Result.success("Payment failure processed")
      end

      def handle_payment_canceled(payment_data)
        order_id = payment_data["orderId"]

        payment_intent = PaymentIntent.find_by(order_id: order_id)
        return Common::Result.failure("Payment intent not found") unless payment_intent

        payment_intent.update!(status: "canceled")

        Common::Result.success("Payment cancellation processed")
      end

      def generate_order_id
        "EXCEL_#{Time.current.strftime('%Y%m%d')}_#{SecureRandom.hex(8)}"
      end
    end
  end
end
