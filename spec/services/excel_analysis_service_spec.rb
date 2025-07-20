# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelAnalysis::Services::FileAnalyzer, type: :service, vcr: true do
  let(:user) { create(:user, credits: 100) }
  let(:excel_file) { create(:excel_file, user: user, status: 'uploaded') }
  let(:service) { described_class.new(excel_file.file_path) }

  before do
    # Mock file system
    allow(File).to receive(:exist?).with(excel_file.file_path).and_return(true)
    allow(FastExcel).to receive(:open).and_return(mock_workbook)
  end

  let(:mock_workbook) do
    double('workbook').tap do |wb|
      allow(wb).to receive(:sheet_names).and_return([ 'Sheet1', 'Sheet2' ])
      allow(wb).to receive(:sheet).and_return(mock_sheet)
    end
  end

  let(:mock_sheet) do
    double('sheet').tap do |sheet|
      allow(sheet).to receive(:rows).and_return([
        [ 'Name', 'Age', 'City' ],
        [ 'John', 25, 'Seoul' ],
        [ 'Jane', 30, 'Busan' ]
      ])
    end
  end

  describe '#perform' do
    context 'with valid file and sufficient tokens' do
      it 'creates analysis with AI insights' do
        result = service.perform(ai_tier: 1, custom_prompt: 'Analyze data structure')

        expect(result[:success]).to be true
        expect(result[:analysis]).to be_persisted
        expect(result[:analysis].insights).to be_present
        expect(result[:analysis].sheet_structure).to be_present
      end

      it 'consumes user tokens' do
        expect {
          service.perform(ai_tier: 1)
        }.to change { user.reload.credits }.by(-5)
      end

      it 'updates excel file status' do
        service.perform(ai_tier: 1)

        expect(excel_file.reload.status).to eq('analyzed')
      end
    end

    context 'with insufficient tokens' do
      before { user.update!(credits: 1) }

      it 'raises insufficient tokens error' do
        expect {
          service.perform(ai_tier: 1)
        }.to raise_error(Common::Errors::InsufficientTokensError)
      end

      it 'does not change file status' do
        begin
          service.perform(ai_tier: 1)
        rescue Common::Errors::InsufficientTokensError
          # Expected error
        end

        expect(excel_file.reload.status).to eq('uploaded')
      end
    end

    context 'with tier 2 analysis for non-pro user' do
      before { user.update!(tier: 'free') }

      it 'raises access denied error' do
        expect {
          service.perform(ai_tier: 2)
        }.to raise_error(Common::Errors::AccessDeniedError)
      end
    end

    context 'with file processing errors' do
      before do
        allow(FastExcel).to receive(:open).and_raise(StandardError, 'Corrupted file')
      end

      it 'handles errors gracefully' do
        result = service.perform(ai_tier: 1)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Corrupted file')
        expect(excel_file.reload.status).to eq('failed')
      end
    end
  end

  describe '#extract_sheet_data' do
    it 'extracts data from all sheets' do
      data = service.send(:extract_sheet_data)

      expect(data).to have_key('Sheet1')
      expect(data).to have_key('Sheet2')
      expect(data['Sheet1'][:headers]).to eq([ 'Name', 'Age', 'City' ])
      expect(data['Sheet1'][:rows]).to include([ 'John', 25, 'Seoul' ])
    end

    it 'handles empty sheets' do
      allow(mock_sheet).to receive(:rows).and_return([])

      data = service.send(:extract_sheet_data)

      expect(data['Sheet1'][:headers]).to eq([])
      expect(data['Sheet1'][:rows]).to eq([])
    end
  end

  describe '#detect_vba_macros' do
    context 'with VBA macros present' do
      before do
        allow(service).to receive(:extract_vba_code).and_return({
          'Module1' => 'Sub Test()\n  MsgBox "Hello"\nEnd Sub'
        })
      end

      it 'analyzes VBA code security' do
        vba_analysis = service.send(:detect_vba_macros)

        expect(vba_analysis[:has_macros]).to be true
        expect(vba_analysis[:modules]).to have_key('Module1')
        expect(vba_analysis[:security_score]).to be_a(Numeric)
        expect(vba_analysis[:risks]).to be_an(Array)
      end
    end

    context 'without VBA macros' do
      before do
        allow(service).to receive(:extract_vba_code).and_return({})
      end

      it 'returns no macro analysis' do
        vba_analysis = service.send(:detect_vba_macros)

        expect(vba_analysis[:has_macros]).to be false
        expect(vba_analysis[:modules]).to be_empty
      end
    end
  end

  describe '#generate_ai_insights' do
    let(:sheet_data) do
      {
        'Sheet1' => {
          headers: [ 'Name', 'Age', 'City' ],
          rows: [ [ 'John', 25, 'Seoul' ], [ 'Jane', 30, 'Busan' ] ],
          statistics: { row_count: 2, column_count: 3 }
        }
      }
    end

    context 'with tier 1 analysis' do
      it 'uses Gemini Flash for analysis' do
        insights = service.send(:generate_ai_insights, sheet_data, 1, 'Analyze this data')

        expect(insights).to have_key(:data_insights)
        expect(insights).to have_key(:recommendations)
        expect(insights).to have_key(:quality_score)
      end
    end

    context 'with tier 2 analysis' do
      before { user.update!(tier: 'pro') }

      it 'uses Claude Sonnet for advanced analysis' do
        insights = service.send(:generate_ai_insights, sheet_data, 2, 'Deep analysis required')

        expect(insights).to have_key(:data_insights)
        expect(insights).to have_key(:recommendations)
        expect(insights).to have_key(:quality_score)
        expect(insights).to have_key(:advanced_patterns)
      end
    end
  end

  describe 'token consumption' do
    it 'calculates correct token cost for tier 1' do
      cost = service.send(:calculate_token_cost, 1, 1000)
      expect(cost).to eq(5) # Base cost for tier 1
    end

    it 'calculates correct token cost for tier 2' do
      cost = service.send(:calculate_token_cost, 2, 1000)
      expect(cost).to eq(25) # Higher cost for tier 2
    end

    it 'includes file size multiplier for large files' do
      large_file_cost = service.send(:calculate_token_cost, 1, 10_000_000) # 10MB
      small_file_cost = service.send(:calculate_token_cost, 1, 1000) # 1KB

      expect(large_file_cost).to be > small_file_cost
    end
  end

  describe 'error handling' do
    it 'handles network timeouts gracefully' do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Net::TimeoutError)

      result = service.perform(ai_tier: 1)

      expect(result[:success]).to be false
      expect(result[:error]).to include('timeout')
    end

    it 'handles API rate limits' do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(
        Net::HTTPTooManyRequests.new('1.1', '429', 'Rate limit exceeded')
      )

      result = service.perform(ai_tier: 1)

      expect(result[:success]).to be false
      expect(result[:error]).to include('rate limit')
    end
  end
end
