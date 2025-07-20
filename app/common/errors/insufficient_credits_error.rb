# frozen_string_literal: true

module Common
  module Errors
    class InsufficientCreditsError < BusinessError
      def initialize(message: "Insufficient credits", details: {})
        super(message: message, code: "INSUFFICIENT_CREDITS", details: details)
      end
    end
  end
end
