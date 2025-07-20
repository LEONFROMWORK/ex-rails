# frozen_string_literal: true

require 'active_job/test_helper'

RSpec.configure do |config|
  config.include ActiveJob::TestHelper

  # Clear all jobs before each test
  config.before(:each) do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  # For tests that need inline job execution
  config.around(:each, :inline_jobs) do |example|
    perform_enqueued_jobs do
      example.run
    end
  end

  # For tests that need to test job enqueueing without execution
  config.around(:each, :test_jobs) do |example|
    # Jobs will be enqueued but not performed automatically
    example.run
  end
end
