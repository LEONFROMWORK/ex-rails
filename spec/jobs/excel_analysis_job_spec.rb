# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelAnalysisJob, type: :job do
  let(:user) { create(:user, credits: 100) }
  let(:excel_file) { create(:excel_file, user: user, status: 'uploaded') }

  describe '#perform' do
    before do
      # Mock the analyzer service
      analyzer_service = instance_double('ExcelAnalyzerService')
      allow(analyzer_service).to receive(:analyze).and_return([
        { type: 'formula_error', location: 'A1', message: 'Invalid formula' },
        { type: 'data_validation', location: 'B2', message: 'Invalid data' }
      ])

      # Mock the AI handler
      ai_handler = instance_double('AiAnalysisHandler')
      allow(ai_handler).to receive(:execute).and_return(
        Common::Result.success({
          analysis: 'AI analysis result',
          tier_used: 'tier1',
          tokens_used: 15,
          confidence_score: 0.95
        })
      )

      # Mock the class initialization
      allow(ExcelAnalysis::AnalyzeErrors::ExcelAnalyzerService).to receive(:new).and_return(analyzer_service)
      allow(AiIntegration::MultiProvider::AiAnalysisHandler).to receive(:new).and_return(ai_handler)
      allow(ActionCable.server).to receive(:broadcast)

      @mock_analyzer = analyzer_service
      @mock_ai_handler = ai_handler
    end

    it 'processes excel file successfully' do
      expect {
        subject.perform(excel_file.id, user.id)
      }.to change { Analysis.count }.by(1)

      excel_file.reload
      expect(excel_file.status).to eq('analyzed')

      user.reload
      expect(user.credits).to eq(85) # 100 - 15

      analysis = Analysis.last
      expect(analysis.ai_tier_used).to eq('tier1')
      expect(analysis.credits_used).to eq(15)
      expect(analysis.confidence_score).to eq(0.95)
    end

    it 'handles cancelled files' do
      excel_file.update!(status: 'cancelled')

      expect {
        subject.perform(excel_file.id, user.id)
      }.not_to change { Analysis.count }

      expect(excel_file.reload.status).to eq('cancelled')
    end

    it 'handles AI analysis failure' do
      allow(@mock_ai_handler).to receive(:execute).and_return(
        Common::Result.failure(
          Common::Errors::BusinessError.new(message: 'AI service unavailable')
        )
      )

      expect {
        subject.perform(excel_file.id, user.id)
      }.not_to change { Analysis.count }

      expect(excel_file.reload.status).to eq('failed')
    end

    it 'broadcasts progress updates' do
      subject.perform(excel_file.id, user.id)

      expect(ActionCable.server).to have_received(:broadcast)
        .with("excel_analysis_#{excel_file.id}", hash_including(type: 'progress'))
        .at_least(:once)
    end

    it 'handles exceptions gracefully' do
      allow(@mock_analyzer).to receive(:analyze).and_raise(StandardError.new('File corrupted'))

      expect {
        subject.perform(excel_file.id, user.id)
      }.not_to change { Analysis.count }

      expect(excel_file.reload.status).to eq('failed')
    end
  end
end
