# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExcelFilesController, type: :controller do
  let(:user) { create(:user, credits: 100) }
  let(:excel_file) { create(:excel_file, user: user) }
  let(:sample_file) { fixture_file_upload('files/sample.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }

  before do
    sign_in_user(user)
    stub_formula_engine_service
    stub_ai_services
  end

  describe 'Authentication and Authorization' do
    context 'when user is not authenticated' do
      before { sign_out_user }

      it 'redirects to login page' do
        get :index
        expect(response).to redirect_to('/auth/login')
      end

      it 'prevents file upload' do
        post :create, params: { file: sample_file }
        expect(response).to redirect_to('/auth/login')
      end
    end

    context 'when user tries to access another user\'s file' do
      let(:other_user) { create(:user) }
      let(:other_excel_file) { create(:excel_file, user: other_user) }

      it 'raises RecordNotFound error' do
        expect {
          get :show, params: { id: other_excel_file.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'GET #index' do
    let!(:excel_files) { create_list(:excel_file, 3, user: user) }

    it 'returns user\'s excel files' do
      get :index

      expect(response).to have_http_status(:success)
      expect(assigns(:excel_files)).to match_array(excel_files)
    end

    it 'includes analyses association' do
      get :index

      # N+1 쿼리 방지 확인
      expect { assigns(:excel_files).each(&:analyses) }.not_to exceed_query_limit(2)
    end
  end

  describe 'GET #show' do
    let!(:analysis) { create(:analysis, excel_file: excel_file, user: user) }

    it 'returns the excel file' do
      get :show, params: { id: excel_file.id }

      expect(response).to have_http_status(:success)
      expect(assigns(:excel_file)).to eq(excel_file)
      expect(assigns(:latest_analysis)).to eq(analysis)
    end

    context 'when file has no formula analysis' do
      before do
        allow_any_instance_of(Analysis).to receive(:has_formula_analysis?).and_return(false)
        allow(excel_file).to receive(:analyzed?).and_return(true)
      end

      it 'triggers formula analysis automatically' do
        expect(ExcelAnalysis::Jobs::AnalyzeFormulaJob).to receive(:perform_later)
          .with(excel_file.id, user.id)

        get :show, params: { id: excel_file.id }
      end
    end
  end

  describe 'POST #create' do
    context 'with valid file' do
      it 'creates excel file and queues for processing' do
        expect {
          post :create, params: { file: sample_file }
        }.to change(ExcelFile, :count).by(1)

        excel_file = ExcelFile.last
        expect(excel_file.user).to eq(user)
        expect(excel_file.original_name).to eq('sample.xlsx')
        expect(response).to redirect_to(excel_file_path(excel_file))
      end

      it 'handles upload through handler' do
        handler_double = instance_double(ExcelUpload::Handlers::UploadExcelHandler)
        allow(ExcelUpload::Handlers::UploadExcelHandler).to receive(:new).and_return(handler_double)
        allow(handler_double).to receive(:call).and_return(
          Common::Result.success(OpenStruct.new(file_id: 123))
        )

        post :create, params: { file: sample_file }

        expect(handler_double).to have_received(:call)
      end
    end

    context 'with invalid file' do
      let(:invalid_file) { fixture_file_upload('spec_helper.rb', 'text/plain') }

      it 'shows error message' do
        handler_double = instance_double(ExcelUpload::Handlers::UploadExcelHandler)
        allow(ExcelUpload::Handlers::UploadExcelHandler).to receive(:new).and_return(handler_double)
        allow(handler_double).to receive(:call).and_return(
          Common::Result.failure([ 'Invalid file format' ])
        )

        post :create, params: { file: invalid_file }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to eq('Invalid file format')
      end
    end
  end

  describe 'POST #analyze' do
    it 'starts analysis through handler' do
      handler_double = instance_double(ExcelAnalysis::Handlers::AnalyzeExcelHandler)
      allow(ExcelAnalysis::Handlers::AnalyzeExcelHandler).to receive(:new).and_return(handler_double)
      allow(handler_double).to receive(:execute).and_return(
        Common::Result.success({ message: 'Analysis started' })
      )

      post :analyze, params: { id: excel_file.id }

      expect(handler_double).to have_received(:execute)
      expect(response).to redirect_to(excel_file)
      expect(flash[:notice]).to eq('Analysis started')
    end

    context 'when analysis fails' do
      it 'shows error message' do
        handler_double = instance_double(ExcelAnalysis::Handlers::AnalyzeExcelHandler)
        allow(ExcelAnalysis::Handlers::AnalyzeExcelHandler).to receive(:new).and_return(handler_double)
        allow(handler_double).to receive(:execute).and_return(
          Common::Result.failure(Common::Errors::ValidationError.new({ errors: [ 'Insufficient credits' ] }))
        )

        post :analyze, params: { id: excel_file.id }

        expect(response).to redirect_to(excel_file)
        expect(flash[:alert]).to eq('Insufficient credits')
      end
    end
  end

  describe 'POST #analyze_formulas' do
    context 'with sufficient credits' do
      it 'performs formula analysis and consumes credits' do
        expect {
          post :analyze_formulas, params: { id: excel_file.id }
        }.to change { user.reload.credits }.by(-5)

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['message']).to eq('수식 분석이 완료되었습니다')
      end

      it 'creates or updates analysis with formula data' do
        post :analyze_formulas, params: { id: excel_file.id }

        analysis = excel_file.reload.latest_analysis
        expect(analysis).to be_present
        expect(analysis.formula_analysis).to be_present
        expect(analysis.formula_count).to eq(10)
        expect(analysis.formula_complexity_score).to eq(2.5)
      end
    end

    context 'with insufficient credits' do
      before { user.update!(credits: 2) }

      it 'returns payment required error' do
        post :analyze_formulas, params: { id: excel_file.id }

        expect(response).to have_http_status(:payment_required)

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('수식 분석을 위해서는 5토큰이 필요합니다')
      end
    end

    context 'when formula analysis service fails' do
      before do
        allow_any_instance_of(ExcelAnalysis::Services::FormulaAnalysisService)
          .to receive(:analyze).and_return(Common::Result.failure('Service unavailable'))
      end

      it 'returns error response' do
        post :analyze_formulas, params: { id: excel_file.id }

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('Service unavailable')
      end
    end
  end

  describe 'GET #formula_results' do
    context 'when formula analysis exists' do
      before do
        analysis = create(:analysis, excel_file: excel_file, user: user,
          formula_analysis: { 'total_formulas' => 15 },
          formula_complexity_score: 3.2,
          formula_count: 15,
          formula_functions: { 'SUM' => 8, 'AVERAGE' => 4 },
          formula_dependencies: [ { 'cell' => 'A1', 'depends_on' => [ 'B1', 'C1' ] } ],
          circular_references: [],
          formula_errors: [ { 'type' => 'REF', 'location' => 'D5' } ],
          formula_optimization_suggestions: [ { 'type' => 'complexity', 'priority' => 'high' } ]
        )
        excel_file.analyses << analysis
      end

      it 'returns formula analysis data' do
        get :formula_results, params: { id: excel_file.id }

        expect(response).to have_http_status(:success)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['analysis']['formula_count']).to eq(15)
        expect(json_response['analysis']['complexity_score']).to eq(3.2)
        expect(json_response['analysis']['complexity_level']).to be_present
      end
    end

    context 'when no formula analysis exists' do
      it 'returns not found error' do
        get :formula_results, params: { id: excel_file.id }

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('수식 분석 결과를 찾을 수 없습니다')
      end
    end
  end

  describe 'GET #download' do
    context 'when file exists' do
      before do
        allow(File).to receive(:exist?).with(excel_file.file_path).and_return(true)
        allow(controller).to receive(:send_file)
      end

      it 'sends the file for download' do
        get :download, params: { id: excel_file.id }

        expect(controller).to have_received(:send_file).with(
          excel_file.file_path,
          filename: excel_file.original_name,
          type: excel_file.content_type,
          disposition: 'attachment'
        )
      end
    end

    context 'when file does not exist' do
      before do
        allow(File).to receive(:exist?).with(excel_file.file_path).and_return(false)
      end

      it 'redirects with error message' do
        get :download, params: { id: excel_file.id }

        expect(response).to redirect_to(excel_file)
        expect(flash[:alert]).to eq('파일을 찾을 수 없습니다')
      end
    end
  end

  describe 'POST #reanalyze' do
    it 'queues file for reanalysis' do
      handler_double = instance_double(ExcelAnalysis::Handlers::AnalyzeExcelHandler)
      allow(ExcelAnalysis::Handlers::AnalyzeExcelHandler).to receive(:new).and_return(handler_double)
      allow(handler_double).to receive(:execute).and_return(
        Common::Result.success({ message: 'Reanalysis started', analysis_id: 456 })
      )

      post :reanalyze, params: { id: excel_file.id }

      expect(response).to have_http_status(:success)

      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be true
      expect(json_response['message']).to eq('Reanalysis started')
      expect(json_response['analysis_id']).to eq(456)
    end
  end

  describe 'GET #progress' do
    it 'returns current file status and progress channel' do
      get :progress, params: { id: excel_file.id }

      expect(response).to have_http_status(:success)

      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be true
      expect(json_response['status']).to eq(excel_file.status)
      expect(json_response['file_id']).to eq(excel_file.id)
      expect(json_response['progress_channel']).to eq("excel_analysis_#{excel_file.id}")
    end
  end

  describe 'Error handling' do
    it 'handles unexpected errors gracefully' do
      allow_any_instance_of(ExcelFile).to receive(:latest_analysis).and_raise(StandardError.new('Database error'))

      expect {
        get :show, params: { id: excel_file.id }
      }.not_to raise_error

      expect(response).to have_http_status(:internal_server_error)
    end

    it 'handles validation errors in handlers' do
      handler_double = instance_double(ExcelAnalysis::Handlers::AnalyzeExcelHandler)
      allow(ExcelAnalysis::Handlers::AnalyzeExcelHandler).to receive(:new).and_return(handler_double)
      allow(handler_double).to receive(:execute).and_return(
        Common::Result.failure(Common::Errors::ValidationError.new({ errors: [ 'File too large' ] }))
      )

      post :analyze, params: { id: excel_file.id }

      expect(response).to redirect_to(excel_file)
      expect(flash[:alert]).to eq('File too large')
    end
  end

  private

  def stub_formula_engine_service
    allow_any_instance_of(ExcelAnalysis::Services::FormulaAnalysisService)
      .to receive(:analyze).and_return(
        Common::Result.success({
          formula_analysis: { 'total_formulas' => 10 },
          formula_complexity_score: 2.5,
          formula_count: 10,
          formula_functions: { 'SUM' => 5, 'AVERAGE' => 3 },
          formula_dependencies: [],
          circular_references: [],
          formula_errors: [],
          formula_optimization_suggestions: []
        })
      )
  end

  def stub_ai_services
    allow_any_instance_of(AiIntegration::MultiProvider::AiAnalysisService)
      .to receive(:analyze).and_return({
        'analysis' => 'Analysis completed successfully',
        'confidence_score' => 0.85,
        'tokens_used' => 50,
        'provider' => 'openai',
        'tier' => 1
      })
  end

  def sign_in_user(user)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:user_signed_in?).and_return(true)
  end

  def sign_out_user
    allow(controller).to receive(:current_user).and_return(nil)
    allow(controller).to receive(:user_signed_in?).and_return(false)
  end
end
