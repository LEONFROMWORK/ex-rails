# frozen_string_literal: true

if defined?(Devise)
  RSpec.configure do |config|
    config.include Devise::Test::ControllerHelpers, type: :controller
    config.include Devise::Test::IntegrationHelpers, type: :request
    config.include Devise::Test::IntegrationHelpers, type: :system
  end
end
