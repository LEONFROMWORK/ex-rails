# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Complete User Workflow', type: :system, js: true do
  let(:email) { 'test@example.com' }
  let(:password) { 'securePassword123!' }
  let(:user_name) { 'Test User' }
  let(:sample_file) { Rails.root.join('spec', 'fixtures', 'files', 'sample.xlsx') }

  before do
    # FormulaEngine 서비스 Mock
    stub_formula_engine_service

    # AI 서비스 Mock
    stub_ai_services
  end

  describe 'Complete User Journey' do
    it 'successfully completes full user registration to analysis workflow' do
      # Step 1: 회원가입
      visit '/auth/register'

      expect(page).to have_content('Create your account')

      fill_in 'user[name]', with: user_name
      fill_in 'user[email]', with: email
      fill_in 'user[password]', with: password
      fill_in 'user[password_confirmation]', with: password

      click_button 'Create account'

      # 회원가입 성공 확인
      expect(page).to have_content('Welcome')
      expect(page).to have_current_path('/')

      # User가 생성되었는지 확인
      user = User.find_by(email: email)
      expect(user).to be_present
      expect(user.name).to eq(user_name)
      expect(user.credits).to eq(100) # 기본 크레딧

      # Step 2: 로그아웃 후 로그인
      click_link 'Logout' # 또는 적절한 로그아웃 링크

      expect(page).to have_content('Successfully logged out')

      # 로그인 페이지로 이동
      visit '/auth/login'

      expect(page).to have_content('Sign In')

      fill_in 'email', with: email
      fill_in 'password', with: password

      click_button 'Sign In'

      # 로그인 성공 확인
      expect(page).to have_content("Welcome back, #{user_name}!")
      expect(page).to have_current_path('/')

      # Step 3: Excel 파일 업로드
      visit '/excel_files/new'

      expect(page).to have_content('Upload Excel File')

      attach_file('file', sample_file)
      click_button 'Upload File'

      # 업로드 성공 확인
      expect(page).to have_content('File uploaded successfully')
      expect(page).to have_content('sample.xlsx')

      excel_file = ExcelFile.last
      expect(excel_file.user).to eq(user)
      expect(excel_file.status).to eq('uploaded')

      # Step 4: 분석 시작
      initial_credits = user.reload.credits

      click_button 'Start Analysis'

      # 분석 시작 확인
      expect(page).to have_content('Analysis Progress')

      # 분석 완료까지 대기 (실제로는 백그라운드 잡)
      sleep(2)

      # 분석 완료 시뮬레이션
      simulate_analysis_completion(excel_file)

      # 결과 확인
      expect(page).to have_content('Analysis Results')
      expect(page).to have_content('Errors Found')
      expect(page).to have_content('Confidence')

      # 크레딧 소모 확인
      final_credits = user.reload.credits
      expect(final_credits).to be < initial_credits

      # Step 5: FormulaEngine 분석
      click_on 'Formula Analysis'

      expect(page).to have_content('Formula Analysis')

      click_button 'Analyze Formulas (5 tokens)'

      # 수식 분석 진행 확인
      expect(page).to have_content('Analyzing Formulas')

      # 수식 분석 완료 시뮬레이션
      simulate_formula_analysis_completion(excel_file)

      # 수식 분석 결과 확인
      expect(page).to have_content('Formula Complexity')
      expect(page).to have_content('Total Formulas')

      # Step 6: 결과 다운로드
      click_link 'Download Original'

      # 다운로드 시작 확인 (실제 파일 다운로드는 브라우저에서 처리)
      expect(page.response_headers['Content-Type']).to include('application/vnd.openxmlformats')
    end
  end

  describe 'Authentication Security' do
    it 'prevents access to protected resources without authentication' do
      # 인증 없이 보호된 페이지 접근 시도
      visit '/excel_files'

      # 로그인 페이지로 리다이렉트
      expect(page).to have_current_path('/auth/login')
      expect(page).to have_content('Please log in to continue')
    end

    it 'handles invalid login credentials' do
      visit '/auth/login'

      fill_in 'email', with: 'wrong@example.com'
      fill_in 'password', with: 'wrongpassword'

      click_button 'Sign In'

      # 에러 메시지 확인
      expect(page).to have_content('Invalid email or password')
      expect(page).to have_current_path('/auth/login')
    end

    it 'validates registration form properly' do
      visit '/auth/register'

      # 빈 폼 제출
      click_button 'Create account'

      # 유효성 검사 에러 확인
      expect(page).to have_content('can\'t be blank')

      # 비밀번호 불일치
      fill_in 'user[name]', with: user_name
      fill_in 'user[email]', with: email
      fill_in 'user[password]', with: password
      fill_in 'user[password_confirmation]', with: 'different_password'

      click_button 'Create account'

      expect(page).to have_content('doesn\'t match')
    end
  end

  describe 'Session Management' do
    let!(:user) { create(:user, email: email, password: password) }

    it 'maintains session across page navigation' do
      # 로그인
      visit '/auth/login'
      fill_in 'email', with: email
      fill_in 'password', with: password
      click_button 'Sign In'

      # 다른 페이지로 이동
      visit '/excel_files'
      expect(page).not_to have_current_path('/auth/login')

      visit '/dashboard'
      expect(page).not_to have_current_path('/auth/login')

      # 사용자 정보가 유지되는지 확인
      expect(page).to have_content(user.name)
    end

    it 'properly handles logout' do
      # 로그인
      visit '/auth/login'
      fill_in 'email', with: email
      fill_in 'password', with: password
      click_button 'Sign In'

      # 로그아웃
      click_link 'Logout'

      expect(page).to have_content('Successfully logged out')

      # 보호된 페이지 접근 시 로그인 페이지로 리다이렉트
      visit '/excel_files'
      expect(page).to have_current_path('/auth/login')
    end
  end

  describe 'Credit System Integration' do
    let!(:user) { create(:user, email: email, password: password, credits: 10) }

    it 'properly tracks and consumes credits' do
      # 로그인
      login_user(user)

      # 파일 업로드
      visit '/excel_files/new'
      attach_file('file', sample_file)
      click_button 'Upload File'

      excel_file = ExcelFile.last

      # 분석 시작 (크레딧 소모)
      click_button 'Start Analysis'

      # 분석 완료 시뮬레이션
      simulate_analysis_completion(excel_file)

      # 크레딧 감소 확인
      expect(user.reload.credits).to be < 10
    end

    it 'prevents analysis when insufficient credits' do
      user.update!(credits: 2)
      login_user(user)

      # 파일 업로드
      visit '/excel_files/new'
      attach_file('file', sample_file)
      click_button 'Upload File'

      # 분석 시도
      click_button 'Start Analysis'

      # 크레딧 부족 메시지 확인
      expect(page).to have_content('Insufficient credits')
    end
  end

  private

  def stub_formula_engine_service
    allow_any_instance_of(FormulaEngineClient).to receive(:create_session).and_return(
      Common::Result.success({ session_id: 'test-session-123' })
    )

    allow_any_instance_of(FormulaEngineClient).to receive(:analyze_formulas).and_return(
      Common::Result.success({
        formula_count: 10,
        complexity_score: 2.5,
        functions: { 'SUM' => 5, 'AVERAGE' => 3 },
        dependencies: [],
        circular_references: [],
        errors: [],
        optimization_suggestions: []
      })
    )

    allow_any_instance_of(FormulaEngineClient).to receive(:load_excel_data).and_return(
      Common::Result.success({})
    )
  end

  def stub_ai_services
    allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService).to receive(:analyze_errors).and_return(
      Common::Result.success({
        analysis: {
          'error_1' => {
            'explanation' => 'Formula reference error detected',
            'impact' => 'High',
            'root_cause' => 'Invalid cell reference',
            'severity' => 'High'
          }
        },
        corrections: [],
        overall_confidence: 0.85,
        summary: 'Excel file analysis completed successfully. Found 2 formula errors.',
        provider_used: 'openai',
        tier_requested: 'tier1',
        tokens_used: 50
      })
    )
  end

  def simulate_analysis_completion(excel_file)
    # 백그라운드 잡 완료 시뮬레이션
    analysis = excel_file.analyses.create!(
      user: excel_file.user,
      status: 'completed',
      detected_errors: [
        { 'type' => 'formula_error', 'message' => 'Invalid reference', 'location' => 'A1' }
      ],
      ai_analysis: 'Analysis completed successfully',
      confidence_score: 0.85,
      ai_tier_used: 1,
      credits_used: 50
    )

    excel_file.update!(status: 'analyzed')

    # 페이지 새로고침으로 결과 표시
    page.refresh
  end

  def simulate_formula_analysis_completion(excel_file)
    analysis = excel_file.latest_analysis
    analysis.update!(
      formula_analysis: { 'total_formulas' => 10 },
      formula_complexity_score: 2.5,
      formula_count: 10,
      formula_functions: { 'SUM' => 5, 'AVERAGE' => 3 },
      formula_dependencies: [],
      circular_references: [],
      formula_errors: [],
      formula_optimization_suggestions: []
    )

    page.refresh
  end

  def login_user(user)
    visit '/auth/login'
    fill_in 'email', with: user.email
    fill_in 'password', with: 'password'
    click_button 'Sign In'
  end
end
