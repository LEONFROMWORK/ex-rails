# frozen_string_literal: true

module AiTestHelpers
  def mock_ai_response(provider: 'openai', tier: 1, confidence: 0.85)
    {
      'message' => "Analysis completed using #{provider}. Found errors in the Excel file.",
      'confidence_score' => confidence,
      'tokens_used' => tier == 1 ? 100 : 250,
      'provider' => provider,
      'structured_analysis' => {
        'errors_found' => rand(1..5),
        'warnings_found' => rand(0..3),
        'optimizations_suggested' => rand(1..4)
      }
    }
  end

  def mock_chat_response(message: 'AI response to your question')
    {
      'message' => message,
      'confidence_score' => 0.9,
      'tokens_used' => 50,
      'provider' => 'openai'
    }
  end

  def stub_all_ai_services
    allow_any_instance_of(Ai::MultiProviderService).to receive(:chat).and_return(mock_chat_response)
    allow_any_instance_of(Ai::MultiProviderService).to receive(:analyze_excel).and_return(mock_ai_response)
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(mock_ai_response)
  end

  def stub_ai_provider_failure(provider)
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_raise(
      StandardError.new("#{provider} service unavailable")
    )
  end

  def stub_ai_escalation_scenario
    # First call returns low confidence (tier 1)
    # Second call returns high confidence (tier 2)
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
      mock_ai_response(confidence: 0.6, tier: 1),
      mock_ai_response(confidence: 0.95, tier: 2, provider: 'anthropic')
    )
  end

  def create_sample_excel_file(user, options = {})
    file_path = Rails.root.join('spec', 'fixtures', 'files', 'sample.xlsx')

    # Ensure the fixtures directory exists
    FileUtils.mkdir_p(File.dirname(file_path))

    # Create a simple Excel file if it doesn't exist
    unless File.exist?(file_path)
      create_test_excel_file(file_path)
    end

    create(:excel_file, {
      user: user,
      original_name: 'sample.xlsx',
      file_path: file_path.to_s,
      file_size: File.size(file_path)
    }.merge(options))
  end

  private

  def create_test_excel_file(path)
    require 'caxlsx'

    package = Axlsx::Package.new
    workbook = package.workbook

    worksheet = workbook.add_worksheet(name: 'Test Sheet')
    worksheet.add_row [ 'Name', 'Value', 'Formula' ]
    worksheet.add_row [ 'Test 1', 100, '=B2*2' ]
    worksheet.add_row [ 'Test 2', 'invalid', '=B3/0' ] # Division by zero error
    worksheet.add_row [ 'Test 3', 300, '=#REF!' ] # Reference error

    package.serialize(path)
  end
end

RSpec.configure do |config|
  config.include AiTestHelpers
end
