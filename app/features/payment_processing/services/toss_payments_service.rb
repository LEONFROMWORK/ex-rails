# frozen_string_literal: true

module PaymentProcessing
  module Services
    class TossPaymentsService
      BASE_URL = "https://api.tosspayments.com/v1"

      def initialize
        @client_key = ENV["TOSS_CLIENT_KEY"]
        @secret_key = ENV["TOSS_SECRET_KEY"]
        @webhook_secret = ENV["TOSS_WEBHOOK_SECRET"]

        validate_configuration
      end

      def create_payment(amount:, order_id:, customer_email:, customer_name:, payment_type:)
        payment_data = {
          amount: amount,
          orderId: order_id,
          orderName: get_order_name(payment_type, amount),
          customerEmail: customer_email,
          customerName: customer_name,
          successUrl: generate_success_url(order_id),
          failUrl: generate_fail_url(order_id)
        }

        response = make_request(
          method: :post,
          endpoint: "/payments",
          data: payment_data
        )

        if response.success?
          payment_response = response.parsed_response

          Common::Result.success({
            payment_key: payment_response["paymentKey"],
            checkout_url: payment_response["checkout"]["url"],
            order_id: order_id
          })
        else
          handle_api_error(response)
        end

      rescue StandardError => e
        Rails.logger.error("TossPayments create_payment failed: #{e.message}")
        Common::Result.failure("Payment creation failed: #{e.message}")
      end

      def confirm_payment(payment_key:, order_id:, amount:)
        confirmation_data = {
          paymentKey: payment_key,
          orderId: order_id,
          amount: amount
        }

        response = make_request(
          method: :post,
          endpoint: "/payments/#{payment_key}",
          data: confirmation_data
        )

        if response.success?
          payment_data = response.parsed_response

          Common::Result.success({
            transactionKey: payment_data["transactionKey"],
            method: payment_data["method"],
            status: payment_data["status"],
            approvedAt: payment_data["approvedAt"]
          })
        else
          handle_api_error(response)
        end

      rescue StandardError => e
        Rails.logger.error("TossPayments confirm_payment failed: #{e.message}")
        Common::Result.failure("Payment confirmation failed: #{e.message}")
      end

      def cancel_payment(payment_key:, cancel_reason:)
        cancellation_data = {
          cancelReason: cancel_reason
        }

        response = make_request(
          method: :post,
          endpoint: "/payments/#{payment_key}/cancel",
          data: cancellation_data
        )

        if response.success?
          Common::Result.success(response.parsed_response)
        else
          handle_api_error(response)
        end

      rescue StandardError => e
        Rails.logger.error("TossPayments cancel_payment failed: #{e.message}")
        Common::Result.failure("Payment cancellation failed: #{e.message}")
      end

      def get_payment(payment_key:)
        response = make_request(
          method: :get,
          endpoint: "/payments/#{payment_key}"
        )

        if response.success?
          Common::Result.success(response.parsed_response)
        else
          handle_api_error(response)
        end

      rescue StandardError => e
        Rails.logger.error("TossPayments get_payment failed: #{e.message}")
        Common::Result.failure("Failed to retrieve payment: #{e.message}")
      end

      def verify_webhook_signature(payload, signature)
        return false unless @webhook_secret.present?

        expected_signature = generate_webhook_signature(payload)
        secure_compare(signature, expected_signature)
      end

      private

      def validate_configuration
        missing_keys = []
        missing_keys << "TOSS_CLIENT_KEY" unless @client_key.present?
        missing_keys << "TOSS_SECRET_KEY" unless @secret_key.present?

        if missing_keys.any?
          raise "TossPayments configuration missing: #{missing_keys.join(', ')}"
        end
      end

      def make_request(method:, endpoint:, data: nil)
        url = "#{BASE_URL}#{endpoint}"

        headers = {
          "Authorization" => "Basic #{encode_credentials}",
          "Content-Type" => "application/json",
          "User-Agent" => "ExcelApp-Rails/1.0"
        }

        options = {
          headers: headers,
          timeout: 30,
          open_timeout: 10
        }

        case method
        when :post
          options[:body] = data.to_json if data
          HTTParty.post(url, options)
        when :get
          HTTParty.get(url, options)
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end
      end

      def encode_credentials
        credentials = "#{@secret_key}:"
        Base64.strict_encode64(credentials)
      end

      def handle_api_error(response)
        error_data = response.parsed_response

        error_message = if error_data.is_a?(Hash)
                          error_data.dig("message") || "Unknown TossPayments error"
        else
                          "TossPayments API error"
        end

        error_code = error_data.dig("code") if error_data.is_a?(Hash)

        Rails.logger.error("TossPayments API error: #{error_message} (Code: #{error_code})")

        Common::Result.failure(
          Common::Errors::BusinessError.new(
            message: error_message,
            code: error_code || "TOSS_API_ERROR",
            details: {
              status_code: response.code,
              response_body: error_data
            }
          )
        )
      end

      def get_order_name(payment_type, amount)
        case payment_type
        when "token_purchase"
          tokens = (amount / 100).to_i
          "ExcelApp 토큰 #{tokens}개 구매"
        when "subscription"
          tier = determine_subscription_tier_by_amount(amount)
          "ExcelApp #{tier.upcase} 구독"
        else
          "ExcelApp 결제"
        end
      end

      def determine_subscription_tier_by_amount(amount)
        case amount
        when 0..9_900
          "basic"
        when 9_900..29_900
          "pro"
        else
          "enterprise"
        end
      end

      def generate_success_url(order_id)
        Rails.application.routes.url_helpers.payment_success_url(
          order_id: order_id,
          host: Rails.application.config.action_mailer.default_url_options[:host]
        )
      end

      def generate_fail_url(order_id)
        Rails.application.routes.url_helpers.payment_fail_url(
          order_id: order_id,
          host: Rails.application.config.action_mailer.default_url_options[:host]
        )
      end

      def generate_webhook_signature(payload)
        OpenSSL::HMAC.hexdigest("SHA256", @webhook_secret, payload)
      end

      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l = a.unpack "C#{a.bytesize}"
        res = 0
        b.each_byte { |byte| res |= byte ^ l.shift }
        res == 0
      end
    end
  end
end
