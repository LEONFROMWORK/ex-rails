# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Error Handling and Recovery Scenarios', type: :system, js: true do
  let(:user) { create(:user, credits: 100) }
  let(:sample_file) { Rails.root.join('spec', 'fixtures', 'files', 'sample.xlsx') }

  before do
    login_as(user)
  end

  describe 'FormulaEngine Service Failure Scenarios' do
    context 'when FormulaEngine service is unavailable' do
      before do
        stub_formula_engine_failure
      end

      it 'handles service connection failure gracefully' do
        excel_file = create(:excel_file, user: user, status: 'analyzed')

        visit excel_file_path(excel_file)
        click_on 'Formula Analysis'

        click_button 'Analyze Formulas (5 tokens)'

        # Should show service unavailable error
        expect(page).to have_content('FormulaEngine service is currently unavailable')
        expect(page).to have_css('.text-red-600')

        # Should not consume credits on failure
        expect(user.reload.credits).to eq(100)

        # Button should be re-enabled for retry
        expect(page).to have_button('Analyze Formulas (5 tokens)', disabled: false)
      end

      it 'provides retry mechanism' do
        excel_file = create(:excel_file, user: user, status: 'analyzed')

        visit excel_file_path(excel_file)
        click_on 'Formula Analysis'

        # First attempt fails
        click_button 'Analyze Formulas (5 tokens)'
        expect(page).to have_content('service is currently unavailable')

        # Fix the service
        stub_formula_engine_success

        # Retry should work
        click_button 'Analyze Formulas (5 tokens)'
        expect(page).to have_content('Analyzing Formulas')
      end
    end

    context 'when FormulaEngine returns invalid response' do
      before do
        stub_formula_engine_invalid_response
      end

      it 'handles malformed response data' do
        excel_file = create(:excel_file, user: user, status: 'analyzed')

        visit excel_file_path(excel_file)
        click_on 'Formula Analysis'

        click_button 'Analyze Formulas (5 tokens)'

        expect(page).to have_content('Invalid response from FormulaEngine')
        expect(page).to have_css('.text-red-600')
      end
    end

    context 'when FormulaEngine times out' do
      before do
        stub_formula_engine_timeout
      end

      it 'handles timeout gracefully' do
        excel_file = create(:excel_file, user: user, status: 'analyzed')

        visit excel_file_path(excel_file)
        click_on 'Formula Analysis'

        click_button 'Analyze Formulas (5 tokens)'

        expect(page).to have_content('Request timeout')
        expect(page).to have_content('Please try again')
      end
    end
  end

  describe 'File Upload Error Scenarios' do
    context 'with invalid file types' do
      let(:text_file) { Rails.root.join('spec', 'spec_helper.rb') }
      let(:image_file) { Rails.root.join('spec', 'fixtures', 'files', 'sample.png') }

      it 'rejects text files with clear error message' do
        visit '/excel_files/new'

        attach_file('file', text_file)
        click_button 'Upload File'

        expect(page).to have_content('Invalid file format')
        expect(page).to have_content('Only Excel files are supported')
        expect(page).to have_css('.text-red-600')

        # Should remain on upload page
        expect(page).to have_current_path('/excel_files')
      end

      it 'rejects image files with appropriate error' do
        visit '/excel_files/new'

        attach_file('file', image_file)
        click_button 'Upload File'

        expect(page).to have_content('Invalid file format')
        expect(page).to have_css('.alert-danger, .text-red-600')
      end
    end

    context 'with corrupted files' do
      before do
        allow_any_instance_of(ExcelUpload::Handlers::UploadExcelHandler)
          .to receive(:call).and_return(
            Common::Result.failure('File appears to be corrupted')
          )
      end

      it 'handles corrupted Excel files' do
        visit '/excel_files/new'

        attach_file('file', sample_file)
        click_button 'Upload File'

        expect(page).to have_content('File appears to be corrupted')
        expect(page).to have_content('Please try uploading a different file')
      end
    end

    context 'with oversized files' do
      before do
        allow_any_instance_of(ActionDispatch::Http::UploadedFile)
          .to receive(:size).and_return(51.megabytes)
      end

      it 'rejects files exceeding size limit' do
        visit '/excel_files/new'

        attach_file('file', sample_file)
        click_button 'Upload File'

        expect(page).to have_content('File size exceeds the maximum limit')
        expect(page).to have_content('Maximum allowed size is 50MB')
      end
    end

    context 'with storage service failures' do
      before do
        allow_any_instance_of(Infrastructure::FileStorage::S3Service)
          .to receive(:upload).and_raise(StandardError.new('Storage service unavailable'))
      end

      it 'handles storage service failures' do
        visit '/excel_files/new'

        attach_file('file', sample_file)
        click_button 'Upload File'

        expect(page).to have_content('File upload failed')
        expect(page).to have_content('Storage service is temporarily unavailable')
      end
    end
  end

  describe 'AI Service Failure Scenarios' do
    context 'when AI service is completely down' do
      before do
        stub_ai_service_failure
      end

      it 'handles AI service unavailability' do
        excel_file = create(:excel_file, user: user, status: 'uploaded')

        visit excel_file_path(excel_file)
        click_button 'Start Analysis'

        # Should show AI service error
        expect(page).to have_content('AI analysis service is currently unavailable')
        expect(page).to have_content('Please try again later')

        # File should remain in uploaded state
        excel_file.reload
        expect(excel_file.status).to eq('uploaded')
      end
    end

    context 'when AI service returns rate limit error' do
      before do
        stub_ai_rate_limit_error
      end

      it 'handles rate limiting gracefully' do
        excel_file = create(:excel_file, user: user, status: 'uploaded')

        visit excel_file_path(excel_file)
        click_button 'Start Analysis'

        expect(page).to have_content('Rate limit exceeded')
        expect(page).to have_content('Please wait a moment before trying again')
      end
    end

    context 'when AI service returns partial results' do
      before do
        stub_ai_partial_failure
      end

      it 'handles partial analysis results' do
        excel_file = create(:excel_file, user: user, status: 'uploaded')

        visit excel_file_path(excel_file)
        click_button 'Start Analysis'

        # Should show warning about partial results
        expect(page).to have_content('Analysis completed with warnings')
        expect(page).to have_content('Some features may not be available')
        expect(page).to have_css('.text-yellow-600')
      end
    end
  end

  describe 'Credit System Error Handling' do
    context 'when user has insufficient credits' do
      before do
        user.update!(credits: 2)
      end

      it 'prevents analysis with clear credit error' do
        excel_file = create(:excel_file, user: user, status: 'uploaded')

        visit excel_file_path(excel_file)
        click_button 'Start Analysis'

        expect(page).to have_content('Insufficient credits')
        expect(page).to have_content('You need at least 5 credits to perform analysis')
        expect(page).to have_link('Purchase Credits')
      end

      it 'prevents formula analysis with specific credit requirement' do
        excel_file = create(:excel_file, user: user, status: 'analyzed')

        visit excel_file_path(excel_file)
        click_on 'Formula Analysis'

        click_button 'Analyze Formulas (5 tokens)'

        expect(page).to have_content('수식 분석을 위해서는 5토큰이 필요합니다')
      end
    end

    context 'when credit deduction fails' do
      before do
        allow_any_instance_of(User).to receive(:consume_credits!)
          .and_raise(StandardError.new('Credit system error'))
      end

      it 'handles credit system failures' do
        excel_file = create(:excel_file, user: user, status: 'uploaded')

        visit excel_file_path(excel_file)
        click_button 'Start Analysis'

        expect(page).to have_content('Credit system error')
        expect(page).to have_content('Please contact support')
      end
    end
  end

  describe 'Network Connectivity Issues' do
    context 'when client loses network connection' do
      it 'handles network disconnection gracefully' do
        excel_file = create(:excel_file, user: user, status: 'processing')

        visit excel_file_path(excel_file)

        # Simulate network disconnection
        page.execute_script('window.navigator.onLine = false')

        # Should show offline indicator
        expect(page).to have_css('[data-connection-status="offline"]')
        expect(page).to have_content('Connection lost')
      end

      it 'attempts to reconnect when network is restored' do
        excel_file = create(:excel_file, user: user, status: 'processing')

        visit excel_file_path(excel_file)

        # Simulate network disconnection then reconnection
        page.execute_script('window.navigator.onLine = false')
        expect(page).to have_content('Connection lost')

        page.execute_script('window.navigator.onLine = true')
        page.execute_script('window.dispatchEvent(new Event("online"))')

        expect(page).to have_content('Connection restored')
      end
    end

    context 'when server is temporarily unavailable' do
      before do
        stub_server_unavailable
      end

      it 'shows server unavailable message' do
        visit '/excel_files'

        expect(page).to have_content('Server temporarily unavailable')
        expect(page).to have_content('Please try again in a few moments')
      end
    end
  end

  describe 'Session Management Errors' do
    context 'when session expires during analysis' do
      it 'handles session expiration gracefully' do
        excel_file = create(:excel_file, user: user, status: 'uploaded')

        visit excel_file_path(excel_file)

        # Simulate session expiration
        page.set_rack_session({})

        click_button 'Start Analysis'

        # Should redirect to login
        expect(page).to have_current_path('/auth/login')
        expect(page).to have_content('Your session has expired')
      end
    end

    context 'when CSRF token is invalid' do
      it 'handles CSRF token mismatch' do
        excel_file = create(:excel_file, user: user, status: 'analyzed')

        visit excel_file_path(excel_file)

        # Invalidate CSRF token
        page.execute_script('document.querySelector(\'[name="csrf-token"]\').content = "invalid"')

        click_on 'Formula Analysis'
        click_button 'Analyze Formulas (5 tokens)'

        expect(page).to have_content('Security token verification failed')
        expect(page).to have_content('Please refresh the page and try again')
      end
    end
  end

  describe 'Database Connection Errors' do
    context 'when database is temporarily unavailable' do
      before do
        allow(ActiveRecord::Base).to receive(:connection)
          .and_raise(ActiveRecord::ConnectionNotEstablished.new('Database unavailable'))
      end

      it 'shows database error page' do
        visit '/excel_files'

        expect(page).to have_content('Database temporarily unavailable')
      end
    end
  end

  describe 'Recovery Mechanisms' do
    context 'automatic retry for transient errors' do
      before do
        @attempt_count = 0
        allow_any_instance_of(FormulaEngineClient).to receive(:analyze_formulas) do
          @attempt_count += 1
          if @attempt_count < 3
            raise Net::TimeoutError.new('Timeout')
          else
            Common::Result.success({ formula_count: 10 })
          end
        end
      end

      it 'automatically retries transient failures' do
        excel_file = create(:excel_file, user: user, status: 'analyzed')

        visit excel_file_path(excel_file)
        click_on 'Formula Analysis'

        click_button 'Analyze Formulas (5 tokens)'

        # Should eventually succeed after retries
        expect(page).to have_content('수식 분석이 완료되었습니다')
      end
    end

    context 'manual retry for persistent errors' do
      it 'provides manual retry button for failed operations' do
        excel_file = create(:excel_file, user: user, status: 'failed')

        visit excel_file_path(excel_file)

        expect(page).to have_button('Retry Analysis')
        expect(page).to have_content('Previous analysis failed')

        # Reset to success for retry
        stub_ai_service_success

        click_button 'Retry Analysis'
        expect(page).to have_content('Analysis started')
      end
    end
  end

  describe 'Error Reporting and Logging' do
    it 'logs errors for debugging purposes' do
      expect(Rails.logger).to receive(:error).with(/FormulaEngine service error/)

      stub_formula_engine_failure

      excel_file = create(:excel_file, user: user, status: 'analyzed')
      visit excel_file_path(excel_file)
      click_on 'Formula Analysis'
      click_button 'Analyze Formulas (5 tokens)'
    end

    it 'provides error context for support' do
      excel_file = create(:excel_file, user: user, status: 'analyzed')

      stub_formula_engine_failure

      visit excel_file_path(excel_file)
      click_on 'Formula Analysis'
      click_button 'Analyze Formulas (5 tokens)'

      # Should show error ID for support reference
      expect(page).to have_content(/Error ID: [a-f0-9-]+/)
      expect(page).to have_link('Contact Support')
    end
  end

  private

  def login_as(user)
    visit '/auth/login'
    fill_in 'email', with: user.email
    fill_in 'password', with: 'password'
    click_button 'Sign In'
  end

  def stub_formula_engine_failure
    allow_any_instance_of(FormulaEngineClient).to receive(:create_session)
      .and_return(Common::Result.failure('Service unavailable'))

    allow_any_instance_of(FormulaEngineClient).to receive(:analyze_formulas)
      .and_return(Common::Result.failure('Service unavailable'))
  end

  def stub_formula_engine_success
    allow_any_instance_of(FormulaEngineClient).to receive(:create_session)
      .and_return(Common::Result.success({ session_id: 'test-session' }))

    allow_any_instance_of(FormulaEngineClient).to receive(:analyze_formulas)
      .and_return(Common::Result.success({ formula_count: 10 }))
  end

  def stub_formula_engine_invalid_response
    allow_any_instance_of(FormulaEngineClient).to receive(:analyze_formulas)
      .and_return(Common::Result.failure('Invalid response format'))
  end

  def stub_formula_engine_timeout
    allow_any_instance_of(FormulaEngineClient).to receive(:analyze_formulas)
      .and_raise(Net::TimeoutError.new('Request timeout'))
  end

  def stub_ai_service_failure
    allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService)
      .to receive(:analyze_errors).and_raise(StandardError.new('AI service unavailable'))
  end

  def stub_ai_rate_limit_error
    allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService)
      .to receive(:analyze_errors).and_raise(StandardError.new('Rate limit exceeded'))
  end

  def stub_ai_partial_failure
    allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService)
      .to receive(:analyze_errors).and_return(
        Common::Result.success({
          analysis: { 'error_1' => { 'explanation' => 'Partial analysis completed' } },
          overall_confidence: 0.4, # Low confidence
          summary: 'Partial analysis completed with warnings',
          provider_used: 'openai',
          tier_requested: 'tier1',
          tokens_used: 50,
          corrections: [],
          warnings: [ 'Some features unavailable' ]
        })
      )
  end

  def stub_ai_service_success
    allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService)
      .to receive(:analyze_errors).and_return(
        Common::Result.success({
          analysis: { 'error_1' => { 'explanation' => 'Analysis completed successfully' } },
          overall_confidence: 0.9,
          summary: 'Analysis completed successfully',
          provider_used: 'openai',
          tier_requested: 'tier1',
          tokens_used: 50,
          corrections: []
        })
      )
  end

  def stub_server_unavailable
    allow_any_instance_of(ApplicationController).to receive(:index)
      .and_raise(StandardError.new('Server unavailable'))
  end
end
