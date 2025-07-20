# frozen_string_literal: true

module Api
  module V1
    class PaymentsController < ApiController
      before_action :authenticate_user!
      before_action :set_payment_service
      before_action :set_payment, only: [ :show, :cancel ]

      # POST /api/v1/payments/request
      def request
        result = @payment_service.request_payment(
          user: current_user,
          amount: payment_params[:amount],
          order_name: payment_params[:order_name],
          method: payment_params[:payment_method] || "card",
          success_url: payment_params[:success_url],
          fail_url: payment_params[:fail_url]
        )

        render json: {
          success: true,
          data: result
        }
      rescue PaymentService::PaymentError => e
        render json: {
          success: false,
          error: e.message
        }, status: :unprocessable_entity
      end

      # POST /api/v1/payments/approve
      def approve
        payment = @payment_service.approve_payment(
          payment_key: approval_params[:payment_key],
          order_id: approval_params[:order_id],
          amount: approval_params[:amount]
        )

        render json: {
          success: true,
          data: {
            payment_id: payment.id,
            status: payment.status,
            transaction_id: payment.transaction_id,
            approved_at: payment.approved_at
          }
        }
      rescue PaymentService::PaymentError => e
        render json: {
          success: false,
          error: e.message
        }, status: :unprocessable_entity
      end

      # GET /api/v1/payments/:id
      def show
        render json: {
          success: true,
          data: payment_json(@payment)
        }
      end

      # POST /api/v1/payments/:id/cancel
      def cancel
        unless @payment.can_cancel?
          return render json: {
            success: false,
            error: "취소할 수 없는 결제 상태입니다"
          }, status: :unprocessable_entity
        end

        payment = @payment_service.cancel_payment(
          payment_key: @payment.transaction_id,
          cancel_reason: cancel_params[:reason],
          cancel_amount: cancel_params[:amount]
        )

        render json: {
          success: true,
          data: payment_json(payment)
        }
      rescue PaymentService::PaymentError => e
        render json: {
          success: false,
          error: e.message
        }, status: :unprocessable_entity
      end

      # GET /api/v1/payments
      def index
        payments = current_user.payments
                              .includes(:user)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(params[:per_page] || 20)

        render json: {
          success: true,
          data: {
            payments: payments.map { |p| payment_json(p) },
            meta: pagination_meta(payments)
          }
        }
      end

      # POST /api/v1/payments/billing_key
      def issue_billing_key
        billing_key = @payment_service.issue_billing_key(
          user: current_user,
          auth_key: billing_key_params[:auth_key],
          customer_key: billing_key_params[:customer_key]
        )

        render json: {
          success: true,
          data: {
            billing_key_id: billing_key.id,
            billing_key: billing_key.billing_key,
            card_number: billing_key.masked_card_number,
            card_brand: billing_key.card_brand
          }
        }
      rescue PaymentService::PaymentError => e
        render json: {
          success: false,
          error: e.message
        }, status: :unprocessable_entity
      end

      # POST /api/v1/payments/billing
      def pay_with_billing
        payment = @payment_service.pay_with_billing_key(
          user: current_user,
          billing_key: billing_params[:billing_key],
          amount: billing_params[:amount],
          order_name: billing_params[:order_name]
        )

        render json: {
          success: true,
          data: payment_json(payment)
        }
      rescue PaymentService::PaymentError => e
        render json: {
          success: false,
          error: e.message
        }, status: :unprocessable_entity
      end

      private

      def set_payment_service
        @payment_service = PaymentService.new
      end

      def set_payment
        @payment = current_user.payments.find(params[:id])
      end

      def payment_params
        params.require(:payment).permit(
          :amount,
          :order_name,
          :payment_method,
          :success_url,
          :fail_url
        )
      end

      def approval_params
        params.require(:payment).permit(:payment_key, :order_id, :amount)
      end

      def cancel_params
        params.require(:payment).permit(:reason, :amount)
      end

      def billing_key_params
        params.require(:billing_key).permit(:auth_key, :customer_key)
      end

      def billing_params
        params.require(:payment).permit(:billing_key, :amount, :order_name)
      end

      def payment_json(payment)
        {
          id: payment.id,
          order_id: payment.order_id,
          transaction_id: payment.transaction_id,
          payment_method: payment.payment_method,
          amount: payment.amount,
          formatted_amount: payment.formatted_amount,
          currency: payment.currency,
          status: payment.status,
          card_number: payment.card_number,
          card_type: payment.card_type,
          receipt_url: payment.receipt_url,
          approved_at: payment.approved_at,
          canceled_at: payment.canceled_at,
          failed_at: payment.failed_at,
          failure_code: payment.failure_code,
          failure_message: payment.failure_message,
          created_at: payment.created_at,
          updated_at: payment.updated_at
        }
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value
        }
      end
    end
  end
end
