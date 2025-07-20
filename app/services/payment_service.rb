# frozen_string_literal: true

class PaymentService
  include HTTParty

  base_uri Rails.env.production? ? "https://api.tosspayments.com" : "https://api.tosspayments.com"

  class PaymentError < StandardError; end
  class InvalidParameterError < PaymentError; end
  class AuthenticationError < PaymentError; end
  class PaymentNotFoundError < PaymentError; end

  def initialize
    @secret_key = Rails.application.credentials.dig(:tosspayments, :secret_key)
    @client_key = Rails.application.credentials.dig(:tosspayments, :client_key)
    @webhook_secret = Rails.application.credentials.dig(:tosspayments, :webhook_secret)

    raise ArgumentError, "TossPayments credentials not configured" unless @secret_key && @client_key
  end

  # 결제 요청
  def request_payment(user:, amount:, order_name:, order_id: nil, method: "card", **options)
    order_id ||= generate_order_id

    payment = user.payments.create!(
      order_id: order_id,
      transaction_id: nil, # Will be set after payment approval
      payment_method: method,
      amount: amount,
      currency: options[:currency] || "KRW",
      status: Payment::STATUSES[:pending],
      metadata: {
        order_name: order_name,
        customer_email: user.email,
        customer_name: user.name,
        **options.slice(:success_url, :fail_url, :customer_mobile_phone)
      }
    )

    {
      payment_id: payment.id,
      order_id: order_id,
      amount: amount,
      order_name: order_name,
      customer_name: user.name,
      customer_email: user.email,
      client_key: @client_key
    }
  rescue StandardError => e
    Rails.logger.error "Payment request failed: #{e.message}"
    raise PaymentError, "결제 요청 실패: #{e.message}"
  end

  # 결제 승인
  def approve_payment(payment_key:, order_id:, amount:)
    payment = Payment.find_by!(order_id: order_id)

    # Validate amount
    if payment.amount != amount
      raise InvalidParameterError, "결제 금액이 일치하지 않습니다"
    end

    response = self.class.post(
      "/v1/payments/confirm",
      headers: auth_headers,
      body: {
        paymentKey: payment_key,
        orderId: order_id,
        amount: amount
      }.to_json
    )

    handle_response(response)

    data = response.parsed_response
    update_payment_from_response(payment, data)

    payment
  rescue StandardError => e
    Rails.logger.error "Payment approval failed: #{e.message}"
    payment&.mark_as_failed!("APPROVAL_FAILED", e.message)
    raise PaymentError, "결제 승인 실패: #{e.message}"
  end

  # 결제 조회
  def get_payment(payment_key: nil, order_id: nil)
    raise ArgumentError, "payment_key or order_id required" unless payment_key || order_id

    if payment_key
      response = self.class.get("/v1/payments/#{payment_key}", headers: auth_headers)
    else
      response = self.class.get("/v1/payments/orders/#{order_id}", headers: auth_headers)
    end

    handle_response(response)
    response.parsed_response
  end

  # 결제 취소
  def cancel_payment(payment_key:, cancel_reason:, cancel_amount: nil)
    payment = Payment.find_by!(transaction_id: payment_key)

    unless payment.can_cancel?
      raise InvalidParameterError, "취소할 수 없는 결제 상태입니다"
    end

    body = {
      cancelReason: cancel_reason
    }
    body[:cancelAmount] = cancel_amount if cancel_amount

    response = self.class.post(
      "/v1/payments/#{payment_key}/cancel",
      headers: auth_headers,
      body: body.to_json
    )

    handle_response(response)

    data = response.parsed_response
    update_payment_from_response(payment, data)

    payment
  rescue StandardError => e
    Rails.logger.error "Payment cancellation failed: #{e.message}"
    raise PaymentError, "결제 취소 실패: #{e.message}"
  end

  # 빌링키 발급
  def issue_billing_key(user:, customer_key: nil, auth_key:)
    customer_key ||= generate_customer_key(user)

    response = self.class.post(
      "/v1/billing/authorizations/issue",
      headers: auth_headers,
      body: {
        authKey: auth_key,
        customerKey: customer_key
      }.to_json
    )

    handle_response(response)

    data = response.parsed_response

    billing_key = user.billing_keys.create!(
      billing_key: data["billingKey"],
      customer_key: customer_key,
      card_number: data["card"]["number"],
      card_type: data["card"]["cardType"],
      card_owner_type: data["card"]["ownerType"],
      issuer_code: data["card"]["issuerCode"],
      acquirer_code: data["card"]["acquirerCode"]
    )

    # Create payment method
    user.payment_methods.create!(
      method_type: "billing_key",
      billing_key: billing_key,
      card_number: data["card"]["number"],
      card_type: data["card"]["cardType"],
      is_default: user.payment_methods.empty?
    )

    billing_key
  rescue StandardError => e
    Rails.logger.error "Billing key issuance failed: #{e.message}"
    raise PaymentError, "빌링키 발급 실패: #{e.message}"
  end

  # 빌링키로 결제
  def pay_with_billing_key(user:, billing_key:, amount:, order_name:, order_id: nil, **options)
    order_id ||= generate_order_id
    billing_key_record = user.billing_keys.find_by!(billing_key: billing_key)

    payment = user.payments.create!(
      order_id: order_id,
      transaction_id: nil,
      payment_method: "billing_key",
      amount: amount,
      currency: options[:currency] || "KRW",
      status: Payment::STATUSES[:pending],
      metadata: {
        order_name: order_name,
        billing_key: billing_key,
        customer_key: billing_key_record.customer_key,
        **options
      }
    )

    response = self.class.post(
      "/v1/billing/#{billing_key}",
      headers: auth_headers,
      body: {
        customerKey: billing_key_record.customer_key,
        amount: amount,
        orderId: order_id,
        orderName: order_name,
        customerEmail: user.email,
        customerName: user.name,
        **options.slice(:taxFreeAmount, :customerMobilePhone)
      }.to_json
    )

    handle_response(response)

    data = response.parsed_response
    update_payment_from_response(payment, data)

    payment
  rescue StandardError => e
    Rails.logger.error "Billing payment failed: #{e.message}"
    payment&.mark_as_failed!("BILLING_FAILED", e.message)
    raise PaymentError, "빌링 결제 실패: #{e.message}"
  end

  # 웹훅 검증
  def verify_webhook(signature:, body:)
    expected_signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", @webhook_secret, body)
    )

    ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end

  # 웹훅 처리
  def process_webhook(event_type:, data:)
    webhook = PaymentWebhook.create!(
      event_type: event_type,
      payment_key: data["paymentKey"],
      order_id: data["orderId"],
      status: data["status"],
      payload: { data: data }
    )

    webhook.process!
    webhook
  end

  private

  def auth_headers
    {
      "Authorization" => "Basic #{Base64.strict_encode64("#{@secret_key}:")}",
      "Content-Type" => "application/json"
    }
  end

  def handle_response(response)
    case response.code
    when 200..299
      # Success
    when 400
      raise InvalidParameterError, response.parsed_response["message"]
    when 401
      raise AuthenticationError, "인증 실패"
    when 404
      raise PaymentNotFoundError, "결제 정보를 찾을 수 없습니다"
    else
      raise PaymentError, response.parsed_response["message"] || "알 수 없는 오류"
    end
  end

  def update_payment_from_response(payment, data)
    payment.update!(
      transaction_id: data["paymentKey"],
      status: data["status"],
      card_number: data.dig("card", "number"),
      card_type: data.dig("card", "cardType"),
      receipt_url: data.dig("receipt", "url"),
      checkout_url: data.dig("checkout", "url"),
      approved_at: data["approvedAt"] ? Time.parse(data["approvedAt"]) : nil,
      metadata: payment.metadata.merge(
        response_data: data
      )
    )
  end

  def generate_order_id
    "ORDER_#{Time.current.strftime('%Y%m%d%H%M%S')}_#{SecureRandom.hex(4).upcase}"
  end

  def generate_customer_key(user)
    "USER_#{user.id}_#{SecureRandom.hex(8).upcase}"
  end
end
