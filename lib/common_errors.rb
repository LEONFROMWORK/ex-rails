# frozen_string_literal: true

# Base error classes for business logic errors
module CommonErrors
  # Base error class for all business errors
  class BusinessError < StandardError
    attr_reader :code, :details

    def initialize(message:, code: nil, details: nil)
      super(message)
      @code = code
      @details = details
    end

    def to_h
      {
        error: self.class.name.demodulize,
        message: message,
        code: code,
        details: details
      }.compact
    end
  end

  # Validation errors
  class ValidationError < BusinessError
    def initialize(message: "Validation failed", details: nil)
      super(message: message, code: "VALIDATION_ERROR", details: details)
    end
  end

  # Authentication errors
  class AuthenticationError < BusinessError
    def initialize(message: "Authentication failed", details: nil)
      super(message: message, code: "AUTH_ERROR", details: details)
    end
  end

  # Authorization errors
  class AuthorizationError < BusinessError
    def initialize(message: "Not authorized", details: nil)
      super(message: message, code: "AUTHZ_ERROR", details: details)
    end
  end

  # Resource not found errors
  class NotFoundError < BusinessError
    def initialize(resource:, id: nil)
      message = id ? "#{resource} with id #{id} not found" : "#{resource} not found"
      super(message: message, code: "NOT_FOUND", details: { resource: resource, id: id })
    end
  end

  # Insufficient tokens error
  class InsufficientTokensError < BusinessError
    def initialize(required:, available:)
      super(
        message: "Insufficient tokens. Required: #{required}, Available: #{available}",
        code: "INSUFFICIENT_TOKENS",
        details: { required: required, available: available }
      )
    end
  end

  # Insufficient credits error (alias for broader credit systems)
  class InsufficientCreditsError < BusinessError
    def initialize(message:, required_tokens: nil, current_tokens: nil)
      super(
        message: message,
        code: "INSUFFICIENT_CREDITS",
        details: { required_tokens: required_tokens, current_tokens: current_tokens }.compact
      )
    end
  end

  # File processing errors
  class FileProcessingError < BusinessError
    def initialize(message:, file_name: nil, details: nil)
      super(
        message: message,
        code: "FILE_PROCESSING_ERROR",
        details: (details || {}).merge(file_name: file_name).compact
      )
    end
  end

  # AI provider errors
  class AIProviderError < BusinessError
    def initialize(provider:, message:, details: nil)
      super(
        message: "AI Provider Error (#{provider}): #{message}",
        code: "AI_PROVIDER_ERROR",
        details: (details || {}).merge(provider: provider)
      )
    end
  end
end

# Create alias for backward compatibility
module Common
  Errors = CommonErrors
end
