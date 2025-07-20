# Manual require for lib files to avoid Zeitwerk conflicts
lib_files_required = []

# Require lib files in specific order to avoid dependencies issues
[
  "lib/result.rb",
  "lib/common_errors.rb",
  "app/common/base_handler.rb",
  "app/common/result.rb",
  "app/common/errors.rb",
  "app/infrastructure/ai_providers/base_provider.rb",
  "app/infrastructure/ai_providers/provider_config.rb",
  "app/infrastructure/ai_providers/rate_limiter.rb",
  "app/infrastructure/ai_providers/open_ai_provider.rb",
  "app/infrastructure/ai_providers/anthropic_provider.rb",
  "app/infrastructure/ai_providers/google_provider.rb",
  "app/infrastructure/ai_providers/open_router_provider.rb",
  "lib/ai/ai_response_cache.rb",
  "lib/ai/response_validation/ai_response_validator.rb",
  "lib/excel/error_detector.rb",
  "lib/excel/file_analyzer.rb",
  "lib/excel/error_analyzer_service.rb"
].each do |file_path|
  full_path = Rails.root.join(file_path)
  if File.exist?(full_path) && !lib_files_required.include?(full_path.to_s)
    require full_path
    lib_files_required << full_path.to_s
  end
end
