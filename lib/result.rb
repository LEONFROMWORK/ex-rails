# frozen_string_literal: true

# Result pattern implementation for handling business logic outcomes
# Success and failure states without exceptions
class Result
  attr_reader :value, :error

  def initialize(success:, value: nil, error: nil)
    @success = success
    @value = value
    @error = error
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def on_success
    yield(value) if success? && block_given?
    self
  end

  def on_failure
    yield(error) if failure? && block_given?
    self
  end

  def value_or(default)
    success? ? value : default
  end

  def self.success(value = nil)
    new(success: true, value: value)
  end

  def self.failure(error)
    new(success: false, error: error)
  end
end

# Create alias for backward compatibility with existing code
module Common
  Result = ::Result
end
