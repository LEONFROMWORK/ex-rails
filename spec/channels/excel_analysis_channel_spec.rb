# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelAnalysisChannel, type: :channel do
  let(:user) { create(:user, credits: 100) }
  let(:excel_file) { create(:excel_file, user: user, status: 'uploaded') }

  before do
    stub_connection current_user: user
  end

  describe '#subscribed' do
    it 'subscribes to the correct stream' do
      subscribe(file_id: excel_file.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("excel_analysis_#{excel_file.id}")
    end

    it 'sends initial status' do
      subscribe(file_id: excel_file.id)

      expect(transmissions.last).to include(
        'type' => 'status',
        'status' => 'uploaded',
        'user_tokens' => 100,
        'can_analyze' => true
      )
    end

    it 'rejects unauthorized access' do
      other_user = create(:user)
      other_file = create(:excel_file, user: other_user)

      subscribe(file_id: other_file.id)

      expect(subscription).to be_rejected
    end

    it 'rejects when user has insufficient tokens' do
      user.update!(credits: 5)

      subscribe(file_id: excel_file.id)

      expect(subscription).to be_rejected
    end
  end

  describe '#request_analysis' do
    before do
      subscribe(file_id: excel_file.id)
      allow(ExcelAnalysis::Handlers::AnalyzeExcelHandler).to receive(:new).and_return(mock_handler)
    end

    let(:mock_handler) do
      instance_double(ExcelAnalysis::Handlers::AnalyzeExcelHandler,
        execute: Common::Result.success(message: 'Analysis queued')
      )
    end

    it 'queues analysis successfully' do
      perform :request_analysis, file_id: excel_file.id

      expect(transmissions.last).to include(
        'type' => 'queued',
        'message' => 'Analysis queued'
      )
    end

    it 'handles handler errors' do
      allow(mock_handler).to receive(:execute).and_return(
        Common::Result.failure(
          Common::Errors::BusinessError.new(message: 'Analysis failed', code: 'ANALYSIS_ERROR')
        )
      )

      perform :request_analysis, file_id: excel_file.id

      expect(transmissions.last).to include(
        'type' => 'error',
        'message' => 'Analysis failed',
        'error_code' => 'ANALYSIS_ERROR'
      )
    end
  end

  describe '#get_analysis_status' do
    let(:analysis) { create(:analysis, excel_file: excel_file, user: user) }

    before do
      subscribe(file_id: excel_file.id)
      analysis
    end

    it 'returns current analysis status' do
      perform :get_analysis_status, file_id: excel_file.id

      expect(transmissions.last).to include(
        'type' => 'analysis_status',
        'status' => excel_file.status,
        'analysis' => hash_including('id' => analysis.id)
      )
    end
  end

  describe '#unsubscribed' do
    it 'cleans up properly' do
      subscribe(file_id: excel_file.id)

      expect { unsubscribe }.not_to raise_error
    end
  end
end
