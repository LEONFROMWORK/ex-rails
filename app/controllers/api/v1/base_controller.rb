# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      protect_from_forgery with: :null_session
      before_action :set_content_type

      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      rescue_from ActionController::ParameterMissing, with: :parameter_missing

      private

      def set_content_type
        response.headers["Content-Type"] = "application/json"
      end

      def current_user
        @current_user ||= authenticate_user_from_token || authenticate_user_from_session
      end

      def authenticate_user!
        unless current_user
          render json: { error: "Authentication required" }, status: :unauthorized
        end
      end

      def authenticate_user_from_token
        auth_token = request.headers["Authorization"]&.sub(/^Bearer /, "")
        return nil unless auth_token

        begin
          decoded = JWT.decode(auth_token, Rails.application.credentials.secret_key_base, true, algorithm: "HS256")
          payload = decoded.first

          return nil if payload["exp"] < Time.current.to_i

          user = User.find_by(id: payload["user_id"])
          return nil unless user&.active?

          user
        rescue JWT::DecodeError, JWT::ExpiredSignature => e
          Rails.logger.warn("JWT authentication failed: #{e.message}")
          nil
        end
      end

      def authenticate_user_from_session
        return nil unless session[:user_id]

        user = User.find_by(id: session[:user_id])
        return nil unless user&.active?

        user
      end

      def record_not_found(exception)
        render json: { error: "Record not found" }, status: :not_found
      end

      def parameter_missing(exception)
        render json: { error: "Parameter missing: #{exception.param}" }, status: :bad_request
      end
    end
  end
end
