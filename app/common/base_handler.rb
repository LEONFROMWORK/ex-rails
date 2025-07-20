# frozen_string_literal: true

module Common
  class BaseHandler
    private

    def success(value = nil)
      Result.success(value)
    end

    def failure(error)
      if error.is_a?(String)
        Result.failure(::Common::Errors::BusinessError.new(message: error))
      else
        Result.failure(error)
      end
    end
  end
end
