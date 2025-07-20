# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiIntegration::ResponseValidation::AiResponseValidator do
  describe '#validate' do
    context 'with valid chat response' do
      let(:valid_response) do
        {
          'message' => 'This is a valid AI response',
          'confidence_score' => 0.85,
          'tokens_used' => 150,
          'provider' => 'openai'
        }
      end

      it 'returns success result' do
        validator = described_class.new(valid_response, expected_type: :chat)
        result = validator.validate

        expect(result).to be_success
        expect(result.value['message']).to eq('This is a valid AI response')
        expect(result.value['confidence_score']).to eq(0.85)
      end
    end

    context 'with valid excel analysis response' do
      let(:valid_excel_response) do
        {
          'message' => 'Excel analysis completed',
          'confidence_score' => 0.92,
          'tokens_used' => 200,
          'provider' => 'anthropic',
          'structured_analysis' => {
            'errors_found' => 5,
            'warnings_found' => 2,
            'optimizations_suggested' => 3
          }
        }
      end

      it 'returns success result' do
        validator = described_class.new(valid_excel_response, expected_type: :excel_analysis)
        result = validator.validate

        expect(result).to be_success
        expect(result.value['structured_analysis']['errors_found']).to eq(5)
      end
    end

    context 'with missing required fields' do
      let(:invalid_response) do
        {
          'message' => 'Incomplete response',
          'confidence_score' => 0.8
          # Missing tokens_used and provider
        }
      end

      it 'returns failure result' do
        validator = described_class.new(invalid_response)
        result = validator.validate

        expect(result).to be_failure
        expect(result.error).to include('Missing required field: tokens_used')
        expect(result.error).to include('Missing required field: provider')
      end
    end

    context 'with invalid confidence score' do
      let(:invalid_confidence_response) do
        {
          'message' => 'Test message',
          'confidence_score' => 1.5, # Invalid: > 1
          'tokens_used' => 100,
          'provider' => 'openai'
        }
      end

      it 'returns failure result' do
        validator = described_class.new(invalid_confidence_response)
        result = validator.validate

        expect(result).to be_failure
        expect(result.error).to include('Invalid confidence_score: must be a number between 0 and 1')
      end
    end

    context 'with harmful content' do
      let(:harmful_response) do
        {
          'message' => 'Your password is: secret123',
          'confidence_score' => 0.8,
          'tokens_used' => 50,
          'provider' => 'openai'
        }
      end

      it 'detects and rejects harmful content' do
        validator = described_class.new(harmful_response)
        result = validator.validate

        expect(result).to be_failure
        expect(result.error).to include('Message contains potentially harmful content')
      end
    end

    context 'with invalid provider' do
      let(:invalid_provider_response) do
        {
          'message' => 'Test message',
          'confidence_score' => 0.8,
          'tokens_used' => 100,
          'provider' => 'unknown_provider'
        }
      end

      it 'returns failure result' do
        validator = described_class.new(invalid_provider_response)
        result = validator.validate

        expect(result).to be_failure
        expect(result.error).to include('Invalid provider: unknown_provider')
      end
    end

    context 'with non-hash input' do
      it 'returns failure result' do
        validator = described_class.new('invalid input')
        result = validator.validate

        expect(result).to be_failure
        expect(result.error).to include('Invalid response format: expected Hash, got String')
      end
    end

    context 'with excel analysis missing structured fields' do
      let(:incomplete_excel_response) do
        {
          'message' => 'Excel analysis',
          'confidence_score' => 0.8,
          'tokens_used' => 100,
          'provider' => 'openai',
          'structured_analysis' => {
            'errors_found' => 5
            # Missing warnings_found and optimizations_suggested
          }
        }
      end

      it 'validates structured analysis fields' do
        validator = described_class.new(incomplete_excel_response, expected_type: :excel_analysis)
        result = validator.validate

        expect(result).to be_failure
        expect(result.error).to include('Missing structured_analysis field: warnings_found')
        expect(result.error).to include('Missing structured_analysis field: optimizations_suggested')
      end
    end
  end

  describe 'response sanitization' do
    let(:response_with_scripts) do
      {
        'message' => 'Hello <script>alert("xss")</script> world',
        'confidence_score' => 0.8,
        'tokens_used' => 100,
        'provider' => 'openai'
      }
    end

    it 'removes harmful scripts from message' do
      validator = described_class.new(response_with_scripts)
      result = validator.validate

      expect(result).to be_success
      expect(result.value['message']).to eq('Hello  world')
    end
  end
end
