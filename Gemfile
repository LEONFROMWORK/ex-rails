source "https://rubygems.org"

ruby "3.4.4"

# Core Rails Framework
gem "rails", "~> 8.0.2"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", "~> 6.0"
gem "importmap-rails"
gem "tailwindcss-rails"
gem "bootsnap", ">= 1.4.4", require: false

# Rails 8 Solid Stack
gem "solid_queue", "~> 1.1"
gem "solid_cable", "~> 3.0"
gem "solid_cache", "~> 1.0"
gem "kamal", "~> 2.3", require: false
gem "thruster", require: false

# Excel Processing
gem "roo", "~> 2.10"                         # Excel file reading and metadata extraction
gem "roo-xls", "~> 1.2"                      # Legacy XLS format support
gem "rubyXL", "~> 3.4"                       # Excel manipulation and VBA analysis
gem "creek", "~> 2.6"                        # Memory-efficient Excel streaming

# High-Performance Excel Processing
gem "fast_excel", "~> 0.4", require: false  # 15.45x faster Excel processing
gem "xlsxtream", "~> 3.1"                    # 36.7x memory efficient Excel generation
gem "memoist", "~> 0.16"                     # Memoization for performance optimization

# AI Integration and HTTP
gem "httparty", "~> 0.22"
gem "faraday", "~> 2.12"
gem "faraday-retry", "~> 2.2"
gem "multi_json", "~> 1.15"
gem "oj", "~> 3.16"

# Vector Database and RAG
gem "pgvector", "~> 0.3"
gem "neighbor", "~> 0.4"
gem "ruby-openai", "~> 7.1"
gem "tiktoken_ruby", "~> 0.0.8"

# Authentication & Security
gem "bcrypt", "~> 3.1"
gem "jwt", "~> 2.9"
gem "rack-attack", "~> 6.7"
gem "rack-cors", "~> 2.0"

# OAuth
gem "omniauth", "~> 2.1"
gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-oauth2", "~> 1.8"
gem "omniauth-rails_csrf_protection", "~> 1.0"

# Redis
gem "redis", "~> 5.3"
gem "hiredis", "~> 0.6"
gem "redis-client", ">= 0.22"

# UI Components
gem "view_component", "~> 3.20"
gem "lookbook", "~> 2.3", group: :development
gem "stimulus-rails"
gem "turbo-rails"
gem "shadcn-ui", "~> 0.0.13"                 # shadcn/ui 컴포넌트 라이브러리
gem "vite_rails", "~> 3.0"                   # Vite integration for Vue.js

# Pagination
gem "kaminari", "~> 1.2"

# Payment processing
gem "stripe", "~> 12.6"                        # Stripe for international payments

# File Storage & External Services
gem "aws-sdk-s3", "~> 1.169"                 # S3 파일 저장 (optional, 환경변수로 제어)
gem "mini_magick", "~> 5.0"                  # 이미지 처리 (멀티모달 AI용)
gem "marcel", "~> 1.0"                       # MIME type detection
# gem "shrine", "~> 3.6"                     # 사용하지 않음 - 자체 S3Service 구현

# Monitoring & Performance
gem "sentry-ruby", "~> 5.22"
gem "sentry-rails", "~> 5.22"
gem "scout_apm", "~> 5.4"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  # Debugging
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "pry-rails"
  gem "pry-byebug"

  # Testing
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.5"
  gem "shoulda-matchers", "~> 6.4"

  # Code Quality
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "simplecov", require: false
  gem "simplecov-console", require: false
end

group :development do
  # Console & Debugging
  gem "web-console"
  gem "listen", "~> 3.9"
  gem "spring"
  gem "foreman"

  # Performance
  gem "bullet", "~> 8.0"
  gem "rack-mini-profiler", "~> 3.3"
  gem "memory_profiler"

  # Documentation
  gem "annotaterb", "~> 4.14"
end

group :test do
  # Testing
  gem "capybara", "~> 3.40"
  gem "selenium-webdriver", "~> 4.27"
  gem "webmock", "~> 3.24"
  gem "vcr", "~> 6.3"
  gem "database_cleaner-active_record", "~> 2.2"

  # Performance Testing
  gem "rspec-benchmark", "~> 0.6"
end
