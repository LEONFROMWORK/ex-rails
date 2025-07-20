require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ExcelappRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # Disable autoload_lib completely to avoid Zeitwerk conflicts
    # config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # i18n configuration
    config.i18n.available_locales = [ :ko, :en ]
    config.i18n.default_locale = :ko
    config.i18n.fallbacks = [ :en ]
    config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml}")]

    # Exclude lib directory from Zeitwerk auto-loading to avoid naming conflicts
    config.autoload_paths -= [ Rails.root.join("lib") ]
    config.eager_load_paths -= [ Rails.root.join("lib") ]

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Add app/features to autoload paths for vertical slice architecture
    config.autoload_paths << Rails.root.join("app", "features")
    config.eager_load_paths << Rails.root.join("app", "features")

    # Add app/domains to autoload paths for domain-driven architecture
    config.autoload_paths << Rails.root.join("app", "domains")
    config.eager_load_paths << Rails.root.join("app", "domains")

    # Active Job configuration
    config.active_job.queue_adapter = :solid_queue
    config.active_job.queue_name_prefix = "excelapp_#{Rails.env}"

    # Set default queue priorities
    config.active_job.default_queue_name = "default"

    # Time zone
    config.time_zone = "Asia/Seoul"

    # Middleware configuration
    config.middleware.use Rack::Attack

    # Feature flags
    config.features = {
      payment_enabled: ENV.fetch("PAYMENT_ENABLED", "false") == "true",
      subscription_required: ENV.fetch("SUBSCRIPTION_REQUIRED", "false") == "true"
    }
  end
end
