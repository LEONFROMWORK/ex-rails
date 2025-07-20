# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      logger.add_tags "ActionCable", current_user&.email || "Anonymous"
    end

    private

    def find_verified_user
      # Authentication via session (for web users)
      if session_user = find_user_by_session
        return session_user
      end

      # Authentication via token (for API users)
      if token_user = find_user_by_token
        return token_user
      end

      # Reject connection if no valid authentication
      reject_unauthorized_connection
    end

    def find_user_by_session
      return nil unless session["user_id"]

      user = User.find_by(id: session["user_id"])
      return nil unless user&.active?

      user
    end

    def find_user_by_token
      auth_token = request.params["token"] || request.headers["Authorization"]&.sub(/^Bearer /, "")
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
  end
end
