# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiIntegration::ResponseValidation::AiResponseValidator do
  describe '#validate' do
    context 'with valid response' do
      let(:valid_response) do
        {
          'message' => 'This is a valid AI response',
          'confidence_score' => 0.85,
          'tokens_used' => 150,
          'provider' => 'openai'
        }
      end

      it 'returns success result' do
        validator = described_class.new(valid_response)
        result = validator.validate

        expect(result).to be_success
        expect(result.value['message']).to eq('This is a valid AI response')
      end
    end

    context 'with missing required fields' do
      let(:invalid_response) do
        {
          'message' => 'Incomplete response'
          # Missing required fields
        }
      end

      it 'returns failure result' do
        validator = described_class.new(invalid_response)
        result = validator.validate

        expect(result).to be_failure
        expect(result.error).to include('Missing required field: tokens_used')
      end
    end
  end
end
