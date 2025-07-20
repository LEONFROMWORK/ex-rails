# frozen_string_literal: true

# Domain-driven architecture autoloader configuration
# Ensures proper loading of domain classes following Vertical Slice architecture

# Domain autoloading is already handled in application.rb
# This file keeps the inflector configuration only

# Configure zeitwerk for domain namespaces
Rails.autoloaders.main.inflector.inflect(
  "ai_integration" => "AiIntegration",
  "excel_analysis" => "ExcelAnalysis",
  "excel_generation" => "ExcelGeneration",
  "vba_analyzer" => "VbaAnalyzer",
  "openrouter_provider" => "OpenrouterProvider"
)
