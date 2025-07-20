# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'
require 'factory_bot_rails'
require 'capybara/rails'
require 'capybara/rspec'
require 'selenium-webdriver'
require 'webmock/rspec'
require 'vcr'

# Require support files
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

# Capybara 설정
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1920,1080')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :headless_chrome
Capybara.default_max_wait_time = 5

# VCR 설정
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.ignore_localhost = true
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [ :method, :uri, :body ]
  }

  # AI API 키 필터링
  config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }
  config.filter_sensitive_data('<GOOGLE_AI_API_KEY>') { ENV['GOOGLE_AI_API_KEY'] }
end

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

RSpec.configure do |config|
  config.fixture_paths = [ "#{::Rails.root}/spec/fixtures" ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot configuration
  config.include FactoryBot::Syntax::Methods

  # Additional includes
  config.include ActiveSupport::Testing::TimeHelpers

  # Database cleaner configuration
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  # 시스템 테스트 설정
  config.before(:each, type: :system) do
    driven_by :headless_chrome
  end

  config.before(:each, type: :system, js: true) do
    driven_by :headless_chrome
  end

  # Mock external API calls by default
  config.before(:each) do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
    allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return('test-key')
    allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return('test-key')
    allow(ENV).to receive(:[]).with('TOSS_CLIENT_KEY').and_return('test-key')
    allow(ENV).to receive(:[]).with('TOSS_SECRET_KEY').and_return('test-key')
  end
end
