# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'File Upload and Analysis Flow', type: :feature, js: true do
  let(:user) { create(:user, credits: 100) }
  let(:sample_file) { Rails.root.join('spec', 'fixtures', 'files', 'sample.xlsx') }
  let(:large_file) { Rails.root.join('spec', 'fixtures', 'files', 'large_sample.xlsx') }

  before do
    # Mock external services
    stub_formula_engine_service
    stub_ai_services
    stub_file_storage

    # Login user
    login_as(user)
  end

  describe 'Complete File Upload to Analysis Flow' do
    context 'with valid Excel file' do
      it 'successfully uploads and analyzes file' do
        visit '/excel_files/new'

        # Step 1: File Upload Interface
        expect(page).to have_content('Upload Excel File')
        expect(page).to have_css('input[type="file"]')
        expect(page).to have_button('Upload File', disabled: false)

        # Step 2: File Selection
        attach_file('file', sample_file)

        # File selection should enable upload button
        expect(page).to have_button('Upload File', disabled: false)

        # Step 3: Upload Process
        initial_file_count = ExcelFile.count

        click_button 'Upload File'

        # Upload should create new ExcelFile record
        expect(ExcelFile.count).to eq(initial_file_count + 1)

        excel_file = ExcelFile.last
        expect(excel_file.user).to eq(user)
        expect(excel_file.original_name).to eq('sample.xlsx')
        expect(excel_file.status).to eq('uploaded')

        # Should redirect to file show page
        expect(page).to have_current_path(excel_file_path(excel_file))
        expect(page).to have_content('File uploaded successfully')

        # Step 4: File Information Display
        expect(page).to have_content('sample.xlsx')
        expect(page).to have_content('uploaded')
        expect(page).to have_content(number_to_human_size(excel_file.file_size))

        # Step 5: Analysis Trigger
        expect(page).to have_button('Start Analysis')

        initial_credits = user.reload.credits

        click_button 'Start Analysis'

        # Analysis should start
        expect(page).to have_content('Analysis in progress')
        expect(page).to have_button('Analyzing...', disabled: true)

        # Wait for background job processing
        perform_enqueued_jobs

        # Step 6: Analysis Completion
        excel_file.reload
        expect(excel_file.status).to eq('analyzed')
        expect(excel_file.analyses.count).to eq(1)

        analysis = excel_file.latest_analysis
        expect(analysis.status).to eq('completed')
        expect(analysis.user).to eq(user)

        # Credits should be consumed
        expect(user.reload.credits).to be < initial_credits

        # Page should show analysis results
        visit current_path # Refresh to see updated results

        expect(page).to have_content('Analysis Results')
        expect(page).to have_content('Confidence')
        expect(page).to have_content('AI Tier')
        expect(page).to have_content('Tokens Used')
      end
    end

    context 'with multiple file formats' do
      let(:xlsx_file) { Rails.root.join('spec', 'fixtures', 'files', 'sample.xlsx') }
      let(:xls_file) { Rails.root.join('spec', 'fixtures', 'files', 'sample.xls') }

      it 'handles different Excel formats' do
        # Test XLSX format
        visit '/excel_files/new'
        attach_file('file', xlsx_file)
        click_button 'Upload File'

        expect(page).to have_content('File uploaded successfully')

        xlsx_file_record = ExcelFile.last
        expect(xlsx_file_record.content_type).to include('spreadsheetml')

        # Test XLS format (if supported)
        visit '/excel_files/new'
        attach_file('file', xls_file)
        click_button 'Upload File'

        expect(page).to have_content('File uploaded successfully')

        xls_file_record = ExcelFile.last
        expect(xls_file_record.content_type).to include('excel')
      end
    end

    context 'with invalid file' do
      let(:invalid_file) { Rails.root.join('spec', 'spec_helper.rb') }

      it 'rejects non-Excel files' do
        visit '/excel_files/new'

        attach_file('file', invalid_file)
        click_button 'Upload File'

        # Should show error message
        expect(page).to have_content('Invalid file format')
        expect(page).to have_css('.text-red-600, .alert-danger')

        # Should remain on upload page
        expect(page).to have_current_path('/excel_files')

        # Should not create ExcelFile record
        expect(ExcelFile.where(original_name: 'spec_helper.rb')).to be_empty
      end
    end

    context 'with oversized file' do
      before do
        # Mock file size validation
        allow_any_instance_of(ActionDispatch::Http::UploadedFile)
          .to receive(:size).and_return(51.megabytes)
      end

      it 'rejects files exceeding size limit' do
        visit '/excel_files/new'

        attach_file('file', sample_file)
        click_button 'Upload File'

        expect(page).to have_content('File size exceeds limit')
        expect(page).to have_css('.text-red-600, .alert-danger')
      end
    end
  end

  describe 'Background Job Processing' do
    let!(:excel_file) { create(:excel_file, user: user, status: 'uploaded') }

    it 'processes analysis job correctly' do
      # Queue analysis job
      ExcelAnalysis::Jobs::AnalyzeExcelJob.perform_later(excel_file.id, user.id)

      # Perform queued jobs
      perform_enqueued_jobs

      # Check job results
      excel_file.reload
      expect(excel_file.status).to eq('analyzed')
      expect(excel_file.analyses.count).to eq(1)

      analysis = excel_file.latest_analysis
      expect(analysis.status).to eq('completed')
      expect(analysis.ai_analysis).to be_present
      expect(analysis.confidence_score).to be > 0
    end

    it 'handles job failures gracefully' do
      # Mock job failure
      allow_any_instance_of(ExcelAnalysis::Jobs::AnalyzeExcelJob)
        .to receive(:perform).and_raise(StandardError.new('Analysis failed'))

      expect {
        ExcelAnalysis::Jobs::AnalyzeExcelJob.perform_later(excel_file.id, user.id)
        perform_enqueued_jobs
      }.not_to raise_error

      # File should be marked as failed
      excel_file.reload
      expect(excel_file.status).to eq('failed')
    end
  end

  describe 'Formula Analysis Integration' do
    let!(:excel_file) { create(:excel_file, user: user, status: 'analyzed') }
    let!(:analysis) { create(:analysis, excel_file: excel_file, user: user) }

    it 'performs formula analysis after main analysis' do
      visit excel_file_path(excel_file)

      # Navigate to Formula Analysis tab
      click_on 'Formula Analysis'

      expect(page).to have_content('Formula Analysis')
      expect(page).to have_button('Analyze Formulas (5 tokens)')

      initial_credits = user.reload.credits

      # Trigger formula analysis
      click_button 'Analyze Formulas (5 tokens)'

      # Should show processing state
      expect(page).to have_content('Analyzing Formulas')

      # Wait for completion
      sleep(2)

      # Should consume credits
      expect(user.reload.credits).to eq(initial_credits - 5)

      # Should display formula analysis results
      page.refresh

      expect(page).to have_content('Formula Complexity')
      expect(page).to have_content('Total Formulas')
      expect(page).to have_content('Function Categories')
    end

    it 'prevents formula analysis with insufficient credits' do
      user.update!(credits: 2)

      visit excel_file_path(excel_file)
      click_on 'Formula Analysis'

      click_button 'Analyze Formulas (5 tokens)'

      # Should show insufficient credits error
      expect(page).to have_content('수식 분석을 위해서는 5토큰이 필요합니다')
    end
  end

  describe 'Real-time Progress Updates' do
    let!(:excel_file) { create(:excel_file, user: user, status: 'uploaded') }

    it 'shows real-time progress via ActionCable' do
      visit excel_file_path(excel_file)

      # Start analysis
      click_button 'Start Analysis'

      # Should show progress container
      expect(page).to have_css('[data-progress-container]', visible: true)

      # Simulate progress updates via ActionCable
      ActionCable.server.broadcast(
        "excel_analysis_#{excel_file.id}",
        {
          type: 'progress_update',
          status: 'processing',
          progress: 50,
          message: 'Analyzing formulas...'
        }
      )

      # Should update progress bar
      expect(page).to have_css('[data-progress="50"]')
      expect(page).to have_content('Analyzing formulas...')

      # Simulate completion
      ActionCable.server.broadcast(
        "excel_analysis_#{excel_file.id}",
        {
          type: 'analysis_complete',
          status: 'completed',
          analysis_id: 123
        }
      )

      # Should show completion state
      expect(page).to have_content('Analysis completed')
    end
  end

  describe 'File Download Functionality' do
    let!(:excel_file) { create(:excel_file, user: user, status: 'analyzed') }

    before do
      # Mock file existence
      allow(File).to receive(:exist?).with(excel_file.file_path).and_return(true)
    end

    it 'allows downloading original file' do
      visit excel_file_path(excel_file)

      expect(page).to have_link('Download Original')

      # Click download link
      click_link 'Download Original'

      # Should trigger file download
      expect(page.response_headers['Content-Disposition'])
        .to include('attachment; filename=')
    end

    it 'handles missing files gracefully' do
      allow(File).to receive(:exist?).with(excel_file.file_path).and_return(false)

      visit excel_file_path(excel_file)
      click_link 'Download Original'

      # Should show error message
      expect(page).to have_content('파일을 찾을 수 없습니다')
    end
  end

  describe 'Error Recovery and Retry' do
    let!(:excel_file) { create(:excel_file, user: user, status: 'failed') }

    it 'allows retrying failed analysis' do
      visit excel_file_path(excel_file)

      # Should show retry option for failed files
      expect(page).to have_button('Retry Analysis')

      # Reset mock to succeed
      stub_ai_services(success: true)

      click_button 'Retry Analysis'

      # Should start new analysis
      expect(page).to have_content('Analysis in progress')

      perform_enqueued_jobs

      # Should succeed this time
      excel_file.reload
      expect(excel_file.status).to eq('analyzed')
    end
  end

  describe 'Multi-user Isolation' do
    let(:other_user) { create(:user) }
    let!(:other_excel_file) { create(:excel_file, user: other_user) }

    it 'prevents access to other users files' do
      # Try to access another user's file
      visit excel_file_path(other_excel_file)

      # Should be redirected or show 404
      expect(page).to have_content('Not Found').or have_current_path('/excel_files')
    end

    it 'shows only user\'s own files in index' do
      user_file = create(:excel_file, user: user)

      visit '/excel_files'

      # Should see own file
      expect(page).to have_content(user_file.original_name)

      # Should not see other user's file
      expect(page).not_to have_content(other_excel_file.original_name)
    end
  end

  private

  def stub_formula_engine_service
    allow_any_instance_of(FormulaEngineClient).to receive(:create_session)
      .and_return(Common::Result.success({ session_id: 'test-session' }))

    allow_any_instance_of(FormulaEngineClient).to receive(:analyze_formulas)
      .and_return(Common::Result.success({
        formula_count: 15,
        complexity_score: 2.8,
        functions: { 'SUM' => 8, 'AVERAGE' => 4, 'IF' => 3 },
        dependencies: [ { 'cell' => 'A1', 'depends_on' => [ 'B1', 'C1' ] } ],
        circular_references: [],
        errors: [],
        optimization_suggestions: [
          { 'type' => 'complexity', 'priority' => 'medium', 'cell' => 'D5' }
        ]
      }))

    allow_any_instance_of(FormulaEngineClient).to receive(:load_excel_data)
      .and_return(Common::Result.success({}))
  end

  def stub_ai_services(success: true)
    if success
      allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService)
        .to receive(:analyze_errors).and_return(
          Common::Result.success({
            analysis: {
              'error_1' => { 'explanation' => 'Excel file analysis completed successfully. Found 3 issues.' }
            },
            overall_confidence: 0.92,
            summary: 'Analysis completed with 3 issues identified.',
            provider_used: 'openai',
            tier_requested: 'tier1',
            tokens_used: 75,
            corrections: []
          })
        )
    else
      allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService)
        .to receive(:analyze_errors).and_raise(StandardError.new('AI service unavailable'))
    end
  end

  def stub_file_storage
    # Mock S3 file operations
    allow_any_instance_of(Infrastructure::FileStorage::S3Service)
      .to receive(:upload).and_return(true)

    allow_any_instance_of(Infrastructure::FileStorage::S3Service)
      .to receive(:delete).and_return(true)
  end

  def login_as(user)
    visit '/auth/login'
    fill_in 'email', with: user.email
    fill_in 'password', with: 'password'
    click_button 'Sign In'
  end

  def perform_enqueued_jobs
    # Process all enqueued jobs
    Sidekiq::Worker.drain_all if defined?(Sidekiq)
    # Or for ActiveJob: ActiveJob::Base.queue_adapter.enqueued_jobs.each { |job| job[:job].perform_now }
  end
end
