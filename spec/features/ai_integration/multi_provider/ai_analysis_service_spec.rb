# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiIntegration::MultiProvider::AiAnalysisService do
  let(:service) { described_class.new(primary_provider: 'openai') }
  let(:file_metadata) do
    {
      name: 'test.xlsx',
      size: 1024,
      sheets: 1,
      rows: 100,
      columns: 10
    }
  end
  let(:errors) do
    [
      {
        type: 'formula_error',
        cell: 'A1',
        value: '#DIV/0!',
        formula: '=B1/C1',
        description: 'Division by zero error'
      }
    ]
  end

  describe '#analyze_errors' do
    context 'when all providers are unavailable' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
        allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
        allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
        allow(ENV).to receive(:[]).with('OPENROUTER_API_KEY').and_return(nil)
      end

      it 'returns failure when no providers are available' do
        result = service.analyze_errors(
          errors: errors,
          file_metadata: file_metadata,
          tier: 'tier1'
        )

        expect(result.failure?).to be true
        expect(result.error).to be_a(Common::Errors::AIProviderError)
      end
    end

    context 'with mock API responses' do
      let(:mock_ai_response) do
        {
          content: {
            "analysis" => {
              "error_1" => {
                "explanation" => "Division by zero error in cell A1",
                "impact" => "High",
                "root_cause" => "Cell C1 contains zero value",
                "severity" => "High"
              }
            },
            "corrections" => [
              {
                "cell" => "A1",
                "original" => "=B1/C1",
                "corrected" => "=IF(C1=0,0,B1/C1)",
                "explanation" => "Add zero check to prevent division by zero",
                "confidence" => 0.95
              }
            ],
            "overall_confidence" => 0.9,
            "summary" => "One division by zero error found and corrected",
            "estimated_time_saved" => "5 minutes"
          }.to_json,
          usage: {
            prompt_credits: 100,
            completion_credits: 150,
            total_credits: 250
          },
          model: 'gpt-3.5-turbo'
        }
      end

      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
        allow_any_instance_of(Infrastructure::AiProviders::OpenAiProvider)
          .to receive(:generate_response)
          .and_return(Common::Result.success(mock_ai_response))
      end

      it 'successfully analyzes errors with tier1' do
        result = service.analyze_errors(
          errors: errors,
          file_metadata: file_metadata,
          tier: 'tier1'
        )

        expect(result.success?).to be true
        expect(result.value[:analysis]).to be_present
        expect(result.value[:corrections]).to be_an(Array)
        expect(result.value[:overall_confidence]).to eq(0.9)
        expect(result.value[:provider_used]).to eq('openai')
        expect(result.value[:tier_used]).to eq('tier1')
      end

      it 'includes token usage in response' do
        result = service.analyze_errors(
          errors: errors,
          file_metadata: file_metadata,
          tier: 'tier1'
        )

        expect(result.value[:credits_used]).to eq(250)
      end
    end

    context 'with user access validation' do
      let(:user_basic) { create(:user, tier: 'basic', credits: 10) }
      let(:user_pro) { create(:user, tier: 'pro', credits: 100) }
      let(:user_poor) { create(:user, tier: 'free', credits: 2) }

      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
      end

      it 'allows tier1 analysis for user with sufficient tokens' do
        expect {
          service.analyze_errors(
            errors: errors,
            file_metadata: file_metadata,
            tier: 'tier1',
            user: user_basic
          )
        }.not_to raise_error
      end

      it 'rejects tier1 analysis for user with insufficient tokens' do
        expect {
          service.analyze_errors(
            errors: errors,
            file_metadata: file_metadata,
            tier: 'tier1',
            user: user_poor
          )
        }.to raise_error(Common::Errors::InsufficientCreditsError)
      end

      it 'allows tier2 analysis for pro user with sufficient tokens' do
        expect {
          service.analyze_errors(
            errors: errors,
            file_metadata: file_metadata,
            tier: 'tier2',
            user: user_pro
          )
        }.not_to raise_error
      end

      it 'rejects tier2 analysis for basic user' do
        expect {
          service.analyze_errors(
            errors: errors,
            file_metadata: file_metadata,
            tier: 'tier2',
            user: user_basic
          )
        }.to raise_error(Common::Errors::InsufficientCreditsError)
      end
    end
  end

  describe '#provider_status' do
    before do
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
      allow(ENV).to receive(:[]).with('ANTHROPIC_API_KEY').and_return(nil)
      allow(ENV).to receive(:[]).with('GOOGLE_API_KEY').and_return(nil)
    end

    it 'returns status of all providers' do
      status = service.provider_status

      expect(status).to be_an(Array)
      expect(status.length).to eq(3)

      openai_status = status.find { |s| s[:name] == 'openai' }
      expect(openai_status[:available]).to be true
      expect(openai_status[:current]).to be true
    end
  end
end
