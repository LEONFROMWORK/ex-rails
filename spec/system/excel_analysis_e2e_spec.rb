# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Excel Analysis E2E Flow', type: :system, js: true do
  let(:user) { create(:user, :pro, credits: 500) }
  let(:sample_file) { Rails.root.join('spec', 'fixtures', 'files', 'sample.xlsx') }

  before do
    # Mock AI services to avoid external API calls
    stub_ai_services

    # Login user
    login_as(user)
  end

  describe 'Complete Excel Analysis Workflow' do
    it 'successfully processes Excel file from upload to results' do
      # Step 1: Upload Excel file
      visit '/excel_files/new'

      expect(page).to have_content('Upload Excel File')

      attach_file('excel_file[file]', sample_file)
      click_button 'Upload File'

      # Should redirect to file show page
      expect(page).to have_content('sample.xlsx')
      expect(page).to have_content('Uploaded')

      # Step 2: Start Analysis
      expect(page).to have_button('Start Analysis')

      # Check user tokens before analysis
      initial_tokens = find('[data-user-tokens]').text.to_i
      expect(initial_tokens).to eq(500)

      click_button 'Start Analysis'

      # Step 3: Real-time Progress Updates
      # The progress section should appear
      expect(page).to have_css('[data-progress-container]', visible: true)
      expect(page).to have_content('Analysis Progress')

      # Progress bar should be visible
      expect(page).to have_css('[data-excel-analysis-target="progressBar"]')

      # Button should be disabled during processing
      expect(page).to have_button('Analyzing...', disabled: true)

      # Wait for progress updates (simulated)
      sleep(1)

      # Step 4: Analysis Completion
      # Mock the completion broadcast
      simulate_analysis_completion

      # Results should appear
      expect(page).to have_content('Analysis Results')
      expect(page).to have_content('Errors Found')
      expect(page).to have_content('Confidence')

      # User tokens should be reduced
      final_tokens = find('[data-user-tokens]').text.to_i
      expect(final_tokens).to be < initial_tokens

      # File status should be updated
      expect(page).to have_content('Analyzed')

      # Step 5: View Detailed Results
      expect(page).to have_content('AI Analysis:')
      expect(page).to have_content('Analysis completed successfully')

      # AI tier and provider information should be displayed
      expect(page).to have_content('AI Tier 1')
      expect(page).to have_content('Provider: openai')
      expect(page).to have_content('Tokens used:')
    end

    it 'handles insufficient tokens gracefully' do
      # Reduce user tokens
      user.update!(credits: 2)

      visit "/excel_files/#{create(:excel_file, user: user).id}"

      click_button 'Start Analysis'

      # Should show error message
      expect(page).to have_content('Insufficient tokens')
      expect(page).to have_css('.text-red-600')

      # Button should remain enabled for retry
      expect(page).to have_button('Start Analysis', disabled: false)
    end

    it 'escalates to tier 2 for complex analysis' do
      # Mock low confidence tier 1 response that escalates to tier 2
      stub_ai_escalation

      excel_file = create(:excel_file, user: user, file_size: 15.megabytes)
      visit "/excel_files/#{excel_file.id}"

      click_button 'Start Analysis'

      # Wait for analysis completion
      sleep(2)
      simulate_tier2_completion

      # Should show tier 2 was used
      expect(page).to have_content('AI Tier 2')
      expect(page).to have_content('Provider: anthropic')

      # Should use more tokens
      final_tokens = find('[data-user-tokens]').text.to_i
      expect(final_tokens).to be <= 200 # More tokens consumed for tier 2
    end
  end

  describe 'Real-time Chat Integration' do
    let(:excel_file) { create(:excel_file, user: user, status: 'analyzed') }
    let(:conversation) { create(:chat_conversation, user: user, excel_file: excel_file) }

    before do
      create(:analysis, excel_file: excel_file, user: user)
    end

    it 'enables AI chat about analyzed file' do
      visit "/chat_conversations/#{conversation.id}"

      expect(page).to have_content('AI Chat')
      expect(page).to have_content(excel_file.original_name)

      # Send a message about the file
      fill_in 'message', with: 'What errors were found in this Excel file?'
      click_button 'Send'

      # Should see the message appear
      expect(page).to have_content('What errors were found in this Excel file?')

      # AI response should appear (mocked)
      expect(page).to have_content('Based on the analysis of your Excel file')

      # User tokens should be consumed
      expect(find('[data-user-tokens]').text.to_i).to be < 500
    end

    it 'allows feedback on AI responses' do
      visit "/chat_conversations/#{conversation.id}"

      # Simulate existing AI message
      create(:chat_message,
        chat_conversation: conversation,
        user: user,
        role: 'assistant',
        content: 'The file contains 2 formula errors in column A.'
      )

      visit current_path # Refresh to see the message

      # Should have feedback buttons
      expect(page).to have_css('.feedback-thumbs-up')
      expect(page).to have_css('.feedback-thumbs-down')

      # Click thumbs up
      find('.feedback-thumbs-up').click

      # Should show feedback form
      expect(page).to have_content('Rate this response')

      select '4', from: 'rating'
      fill_in 'feedback_text', with: 'Very helpful analysis!'
      click_button 'Submit Feedback'

      # Feedback should be recorded
      expect(page).to have_content('Thank you for your feedback')
    end
  end

  describe 'Admin Cache Management' do
    let(:admin) { create(:user, :admin) }

    before do
      logout
      login_as(admin)
    end

    it 'allows admin to view and manage AI cache' do
      visit '/admin/ai_cache'

      expect(page).to have_content('AI Cache Management')
      expect(page).to have_content('Hit Rate')
      expect(page).to have_content('Cache Hits')
      expect(page).to have_content('Total Keys')

      # Should have management buttons
      expect(page).to have_button('Clear Expired Entries')
      expect(page).to have_button('Clear All Cache')

      # Test clearing expired entries
      click_button 'Clear Expired Entries'

      expect(page).to have_content('Cleared')
      expect(page).to have_content('expired cache entries')
    end

    it 'provides cache performance recommendations' do
      visit '/admin/ai_cache'

      # Should show performance section
      expect(page).to have_content('Performance Recommendations')

      # Mock different cache states and verify recommendations
      expect(page).to have_css('.text-green-600, .text-yellow-600, .text-red-600, .text-blue-600')
    end
  end

  describe 'Error Handling and Edge Cases' do
    it 'handles file upload errors gracefully' do
      visit '/excel_files/new'

      # Try to upload non-Excel file
      attach_file('excel_file[file]', Rails.root.join('spec', 'spec_helper.rb'))
      click_button 'Upload File'

      expect(page).to have_content('Invalid file format')
      expect(page).to have_css('.text-red-600')
    end

    it 'handles analysis failures gracefully' do
      # Mock analysis failure
      stub_ai_failure

      excel_file = create(:excel_file, user: user)
      visit "/excel_files/#{excel_file.id}"

      click_button 'Start Analysis'

      # Should show error message
      expect(page).to have_content('Analysis failed')
      expect(page).to have_css('.text-red-600')

      # Button should be re-enabled for retry
      expect(page).to have_button('Start Analysis', disabled: false)
    end

    it 'handles network connectivity issues' do
      # Mock network timeout
      stub_ai_timeout

      excel_file = create(:excel_file, user: user)
      visit "/excel_files/#{excel_file.id}"

      click_button 'Start Analysis'

      # Should show timeout message
      expect(page).to have_content('Request timeout')
      expect(page).to have_button('Start Analysis', disabled: false)
    end

    it 'maintains session state during long analysis' do
      excel_file = create(:excel_file, user: user)
      visit "/excel_files/#{excel_file.id}"

      # Start analysis
      click_button 'Start Analysis'

      # Navigate away and back
      visit '/excel_files'
      visit "/excel_files/#{excel_file.id}"

      # Should maintain connection and show progress
      expect(page).to have_css('[data-connection-status]')
      expect(page).to have_content('Analysis Progress')
    end
  end

  describe 'Performance and Responsiveness' do
    it 'handles large file uploads efficiently' do
      # Mock large file
      large_file = create(:excel_file, user: user, file_size: 25.megabytes)

      visit "/excel_files/#{large_file.id}"

      start_time = Time.current
      click_button 'Start Analysis'

      # Should start processing quickly
      expect(page).to have_content('Analysis Progress', wait: 5)

      response_time = Time.current - start_time
      expect(response_time).to be < 5.seconds
    end

    it 'provides responsive UI updates' do
      excel_file = create(:excel_file, user: user)
      visit "/excel_files/#{excel_file.id}"

      # UI should be responsive to user actions
      click_button 'Refresh Status'

      # Should update without full page reload
      expect(page).not_to have_css('.loading-spinner', wait: 2)

      # Connection status should be visible
      expect(page).to have_css('[data-connection-status]')
    end
  end

  private

  def stub_ai_services
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
      {
        'message' => 'Analysis completed successfully. Found 2 errors in the Excel file.',
        'confidence_score' => 0.85,
        'tokens_used' => 100,
        'provider' => 'openai',
        'structured_analysis' => {
          'errors_found' => 2,
          'warnings_found' => 1,
          'optimizations_suggested' => 3
        }
      }
    )
  end

  def stub_ai_escalation
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_return(
      {
        'message' => 'Initial analysis complete',
        'confidence_score' => 0.6, # Low confidence triggers escalation
        'tokens_used' => 100,
        'provider' => 'openai'
      },
      {
        'message' => 'Advanced analysis completed with high accuracy',
        'confidence_score' => 0.95,
        'tokens_used' => 250,
        'provider' => 'anthropic'
      }
    )
  end

  def stub_ai_failure
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_raise(
      StandardError.new('AI service temporarily unavailable')
    )
  end

  def stub_ai_timeout
    allow_any_instance_of(Ai::MultiProviderService).to receive(:send_request).and_raise(
      Net::ReadTimeout.new('Request timeout')
    )
  end

  def simulate_analysis_completion
    # This would trigger the JavaScript to update the UI
    page.execute_script("""
      const event = new CustomEvent('analysisComplete', {
        detail: {
          status: 'completed',
          errors_found: 2,
          confidence_score: 85,
          ai_tier_used: 1,
          tokens_used: 100,
          provider: 'openai'
        }
      });
      document.dispatchEvent(event);
    """)
  end

  def simulate_tier2_completion
    page.execute_script("""
      const event = new CustomEvent('analysisComplete', {
        detail: {
          status: 'completed',
          errors_found: 5,
          confidence_score: 95,
          ai_tier_used: 2,
          tokens_used: 300,
          provider: 'anthropic'
        }
      });
      document.dispatchEvent(event);
    """)
  end

  def login_as(user)
    visit '/auth/login'
    fill_in 'email', with: user.email
    fill_in 'password', with: 'password123'
    click_button 'Sign In'
  end

  def logout
    visit '/auth/logout'
  end
end
