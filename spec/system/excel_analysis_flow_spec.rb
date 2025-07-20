# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Excel Analysis Flow', type: :system, vcr: true do
  let(:user) { create(:user, credits: 100) }

  before do
    sign_in user
    driven_by(:headless_chrome)
  end

  describe 'Complete excel analysis workflow' do
    it 'uploads file and performs full analysis', :js do
      visit dashboard_index_path

      # File upload section
      expect(page).to have_text('Upload Excel File')

      within('[data-testid="upload-section"]') do
        attach_file('excel_file[file]', Rails.root.join('spec/fixtures/sample.xlsx'))
        click_button 'Upload File'
      end

      # Wait for upload completion
      expect(page).to have_text('File uploaded successfully', wait: 10)

      # Navigate to file analysis
      click_link 'View Analysis'

      # Check file details are displayed
      expect(page).to have_text('sample.xlsx')
      expect(page).to have_text('File Details')

      # Trigger AI analysis
      within('[data-testid="analysis-controls"]') do
        select 'Tier 1 (Gemini Flash)', from: 'AI Tier'
        fill_in 'Custom prompt', with: 'Analyze the data structure and provide insights'
        click_button 'Start Analysis'
      end

      # Wait for analysis completion
      expect(page).to have_text('Analysis completed', wait: 30)

      # Verify analysis results
      expect(page).to have_text('Data Insights')
      expect(page).to have_text('Sheet Structure')
      expect(page).to have_text('Recommendations')

      # Check VBA analysis if available
      if page.has_text?('VBA Analysis')
        within('[data-testid="vba-analysis"]') do
          expect(page).to have_text('Security Score')
          expect(page).to have_text('Code Quality')
        end
      end

      # Test export functionality
      within('[data-testid="export-controls"]') do
        select 'JSON', from: 'Export Format'
        click_button 'Export Analysis'
      end

      # Verify export download
      expect(page.response_headers['Content-Type']).to include('application/json')
    end

    it 'handles insufficient credits gracefully' do
      user.update!(credits: 1)

      visit dashboard_index_path

      within('[data-testid="upload-section"]') do
        attach_file('excel_file[file]', Rails.root.join('spec/fixtures/sample.xlsx'))
        click_button 'Upload File'
      end

      click_link 'View Analysis'

      within('[data-testid="analysis-controls"]') do
        select 'Tier 2 (Claude Sonnet)', from: 'AI Tier'
        click_button 'Start Analysis'
      end

      expect(page).to have_text('Insufficient tokens')
      expect(page).to have_text('Upgrade your plan')
    end

    it 'supports template-based generation' do
      visit dashboard_index_path

      # Navigate to template generation
      click_link 'Generate Template'

      within('[data-testid="template-generator"]') do
        select 'Financial Report', from: 'Template Type'
        fill_in 'Rows', with: '100'
        fill_in 'Columns', with: '10'
        click_button 'Generate Excel'
      end

      # Wait for generation
      expect(page).to have_text('Template generated successfully', wait: 15)

      # Verify download
      expect(page).to have_link('Download Excel Template')
    end
  end

  describe 'File management' do
    let!(:excel_file) { create(:excel_file, user: user, status: 'uploaded') }

    it 'displays user files in dashboard' do
      visit dashboard_index_path

      within('[data-testid="file-list"]') do
        expect(page).to have_text(excel_file.original_name)
        expect(page).to have_text('Uploaded')
      end
    end

    it 'allows file deletion' do
      visit dashboard_index_path

      within("[data-testid=\"file-#{excel_file.id}\"]") do
        click_button 'Delete'
      end

      # Confirm deletion
      within('[data-testid="confirmation-modal"]') do
        click_button 'Confirm Delete'
      end

      expect(page).to have_text('File deleted successfully')
      expect(page).not_to have_text(excel_file.original_name)
    end
  end

  describe 'Chat functionality' do
    let!(:excel_file) { create(:excel_file, user: user, status: 'analyzed') }
    let!(:analysis) { create(:analysis, excel_file: excel_file) }

    it 'enables chat about analysis results', :js do
      visit excel_file_path(excel_file)

      # Open chat interface
      click_button 'Chat about this file'

      within('[data-testid="chat-interface"]') do
        fill_in 'Message', with: 'What are the key insights from this data?'
        click_button 'Send'
      end

      # Wait for AI response
      expect(page).to have_text('Based on the analysis', wait: 15)

      # Verify chat history
      within('[data-testid="chat-history"]') do
        expect(page).to have_text('What are the key insights')
        expect(page).to have_text('Based on the analysis')
      end
    end
  end

  describe 'Payment integration' do
    it 'handles credits purchase flow' do
      user.update!(credits: 0)

      visit dashboard_index_path

      # Navigate to credits purchase
      click_link 'Buy Credits'

      within('[data-testid="credits-packages"]') do
        click_button 'Buy 100 Credits'
      end

      # Mock Toss Payments integration
      expect(page).to have_text('Redirecting to payment')

      # Simulate successful payment callback
      visit payment_success_path(amount: 10000, credits: 100)

      expect(page).to have_text('Payment successful')
      expect(user.reload.credits).to eq(100)
    end
  end
end
