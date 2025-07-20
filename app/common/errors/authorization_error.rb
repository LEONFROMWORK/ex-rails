# frozen_string_literal: true

module Common
  module Errors
    class AuthorizationError < BusinessError
      def initialize(message: "Unauthorized access", details: {})
        super(message: message, code: "UNAUTHORIZED", details: details)
      end
    end
  end
end
