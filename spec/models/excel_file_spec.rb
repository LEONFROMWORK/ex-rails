# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelFile, type: :model do
  let(:user) { create(:user) }
  let(:excel_file) { create(:excel_file, user: user) }

  describe 'associations' do
    it 'belongs to user' do
      expect(excel_file.user).to eq(user)
    end

    it 'has many analyses' do
      analysis1 = create(:analysis, excel_file: excel_file)
      analysis2 = create(:analysis, excel_file: excel_file)

      expect(excel_file.analyses).to include(analysis1, analysis2)
    end
  end

  describe 'validations' do
    it 'validates presence of original_name' do
      excel_file.original_name = nil
      expect(excel_file).not_to be_valid
      expect(excel_file.errors[:original_name]).to include("can't be blank")
    end

    it 'validates presence of file_path' do
      excel_file.file_path = nil
      expect(excel_file).not_to be_valid
      expect(excel_file.errors[:file_path]).to include("can't be blank")
    end

    it 'validates presence of file_size' do
      excel_file.file_size = nil
      expect(excel_file).not_to be_valid
      expect(excel_file.errors[:file_size]).to include("can't be blank")
    end

    it 'validates file_size is greater than 0' do
      excel_file.file_size = 0
      expect(excel_file).not_to be_valid
      expect(excel_file.errors[:file_size]).to include("must be greater than 0")
    end
  end

  describe 'enums' do
    it 'defines status enum' do
      expect(ExcelFile.statuses).to eq({
        'uploaded' => 0,
        'processing' => 1,
        'analyzed' => 2,
        'failed' => 3,
        'cancelled' => 4
      })
    end
  end

  describe 'scopes' do
    let!(:recent_file) { create(:excel_file, user: user, created_at: 1.day.ago) }
    let!(:old_file) { create(:excel_file, user: user, created_at: 1.week.ago) }

    it 'orders by created_at desc for recent scope' do
      expect(ExcelFile.recent.first).to eq(recent_file)
    end

    it 'filters by status' do
      analyzed_file = create(:excel_file, user: user, status: 'analyzed')
      expect(ExcelFile.analyzed).to include(analyzed_file)
      expect(ExcelFile.analyzed).not_to include(excel_file)
    end
  end

  describe '#latest_analysis' do
    it 'returns the most recent analysis' do
      old_analysis = create(:analysis, excel_file: excel_file, created_at: 1.day.ago)
      new_analysis = create(:analysis, excel_file: excel_file, created_at: 1.hour.ago)

      expect(excel_file.latest_analysis).to eq(new_analysis)
    end

    it 'returns nil when no analyses exist' do
      expect(excel_file.latest_analysis).to be_nil
    end
  end

  describe '#can_be_analyzed?' do
    it 'returns true for uploaded files' do
      excel_file.update!(status: 'uploaded')
      expect(excel_file.can_be_analyzed?).to be true
    end

    it 'returns true for failed files' do
      excel_file.update!(status: 'failed')
      expect(excel_file.can_be_analyzed?).to be true
    end

    it 'returns false for processing files' do
      excel_file.update!(status: 'processing')
      expect(excel_file.can_be_analyzed?).to be false
    end
  end

  describe '#can_be_cancelled?' do
    it 'returns true for uploaded files' do
      excel_file.update!(status: 'uploaded')
      expect(excel_file.can_be_cancelled?).to be true
    end

    it 'returns true for processing files' do
      excel_file.update!(status: 'processing')
      expect(excel_file.can_be_cancelled?).to be true
    end

    it 'returns false for analyzed files' do
      excel_file.update!(status: 'analyzed')
      expect(excel_file.can_be_cancelled?).to be false
    end
  end

  describe '#analysis_progress' do
    it 'returns correct progress for different statuses' do
      expect(excel_file.analysis_progress).to eq(10) # uploaded

      excel_file.update!(status: 'processing')
      expect(excel_file.analysis_progress).to eq(50)

      excel_file.update!(status: 'analyzed')
      expect(excel_file.analysis_progress).to eq(100)

      excel_file.update!(status: 'failed')
      expect(excel_file.analysis_progress).to eq(0)
    end
  end

  describe '#file_extension' do
    it 'returns the file extension' do
      excel_file.update!(original_name: 'test.xlsx')
      expect(excel_file.file_extension).to eq('.xlsx')
    end
  end

  describe '#human_file_size' do
    it 'returns human readable file size' do
      excel_file.update!(file_size: 1024)
      expect(excel_file.human_file_size).to eq('1.0 KB')

      excel_file.update!(file_size: 1024 * 1024)
      expect(excel_file.human_file_size).to eq('1.0 MB')
    end
  end

  describe '#processing_time' do
    it 'returns processing time for analyzed files' do
      excel_file.update!(status: 'analyzed', created_at: 1.hour.ago)
      analysis = create(:analysis, excel_file: excel_file, created_at: 30.minutes.ago)

      expect(excel_file.processing_time).to be_within(1).of(30.minutes)
    end

    it 'returns nil for non-analyzed files' do
      excel_file.update!(status: 'uploaded')
      expect(excel_file.processing_time).to be_nil
    end
  end
end
