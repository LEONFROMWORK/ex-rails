# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelUpload::Handlers::ProcessUploadHandler do
  let(:user) { create(:user, credits: 50) }
  let(:file) { fixture_file_upload('sample.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }

  subject { described_class.new(file: file, user: user) }

  describe '#execute' do
    before do
      allow(ExcelAnalysisJob).to receive(:perform_later)
    end

    context 'with valid file' do
      it 'processes file successfully' do
        result = subject.execute

        expect(result).to be_success
        expect(result.value).to include(:file_id, :message)
        expect(ExcelFile.count).to eq(1)
        expect(ExcelAnalysisJob).to have_received(:perform_later)
      end

      it 'creates excel file record' do
        subject.execute

        excel_file = ExcelFile.last
        expect(excel_file.user).to eq(user)
        expect(excel_file.original_name).to eq('sample.xlsx')
        expect(excel_file.status).to eq('uploaded')
        expect(excel_file.file_size).to be > 0
      end

      it 'saves file to disk' do
        result = subject.execute

        excel_file = ExcelFile.find(result.value[:file_id])
        expect(File.exist?(excel_file.file_path)).to be true
      end
    end

    context 'with insufficient tokens' do
      let(:user) { create(:user, credits: 5) }

      it 'returns error' do
        result = subject.execute

        expect(result).to be_failure
        expect(result.error.code).to eq('INSUFFICIENT_TOKENS')
        expect(ExcelFile.count).to eq(0)
      end
    end

    context 'with invalid file' do
      let(:file) { fixture_file_upload('large_file.txt', 'text/plain') }

      it 'rejects invalid file type' do
        result = subject.execute

        expect(result).to be_failure
        expect(result.error.message).to include('Invalid file type')
        expect(ExcelFile.count).to eq(0)
      end
    end

    context 'with no file' do
      let(:file) { nil }

      it 'returns error' do
        result = subject.execute

        expect(result).to be_failure
        expect(result.error.message).to eq('File is required')
        expect(ExcelFile.count).to eq(0)
      end
    end

    context 'with oversized file' do
      before do
        stub_const('ExcelUpload::Handlers::ProcessUploadHandler::MAX_FILE_SIZE', 1.kilobyte)
      end

      it 'rejects oversized file' do
        result = subject.execute

        expect(result).to be_failure
        expect(result.error.message).to include('File too large')
        expect(ExcelFile.count).to eq(0)
      end
    end
  end
end
