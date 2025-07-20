# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::FilesController, type: :controller do
  let(:user) { create(:user, credits: 100) }
  let(:excel_file) { create(:excel_file, user: user) }

  before do
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'GET #index' do
    let!(:files) { create_list(:excel_file, 3, user: user) }

    it 'returns user files' do
      get :index

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['files'].size).to eq(3)
    end

    it 'includes pagination' do
      get :index

      json = JSON.parse(response.body)
      expect(json).to have_key('pagination')
      expect(json['pagination']).to include('current_page', 'total_pages', 'total_count')
    end
  end

  describe 'GET #show' do
    it 'returns file details' do
      get :show, params: { id: excel_file.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['file']).to include(
        'id' => excel_file.id,
        'original_name' => excel_file.original_name,
        'status' => excel_file.status
      )
    end

    it 'returns 404 for non-existent file' do
      get :show, params: { id: 999 }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for other user files' do
      other_user = create(:user)
      other_file = create(:excel_file, user: other_user)

      get :show, params: { id: other_file.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    let(:file) { fixture_file_upload('sample.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }

    before do
      allow(ExcelUpload::Handlers::ProcessUploadHandler).to receive(:new).and_return(mock_handler)
    end

    let(:mock_handler) do
      instance_double(ExcelUpload::Handlers::ProcessUploadHandler,
        execute: Common::Result.success(file_id: 123, message: 'File uploaded')
      )
    end

    it 'uploads file successfully' do
      post :create, params: { file: file }

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json).to include('file_id' => 123, 'message' => 'File uploaded')
    end

    it 'handles upload errors' do
      allow(mock_handler).to receive(:execute).and_return(
        Common::Result.failure(
          Common::Errors::ValidationError.new(message: 'Invalid file')
        )
      )

      post :create, params: { file: file }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to eq('Invalid file')
    end
  end

  describe 'DELETE #destroy' do
    it 'deletes file successfully' do
      delete :destroy, params: { id: excel_file.id }

      expect(response).to have_http_status(:ok)
      expect(ExcelFile.exists?(excel_file.id)).to be false
    end

    it 'returns 404 for non-existent file' do
      delete :destroy, params: { id: 999 }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #cancel' do
    let(:excel_file) { create(:excel_file, user: user, status: 'processing') }

    before do
      allow(ExcelAnalysis::Handlers::CancelAnalysisHandler).to receive(:new).and_return(mock_handler)
    end

    let(:mock_handler) do
      instance_double(ExcelAnalysis::Handlers::CancelAnalysisHandler,
        execute: Common::Result.success(message: 'Analysis cancelled')
      )
    end

    it 'cancels analysis successfully' do
      post :cancel, params: { id: excel_file.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to include('success' => true, 'message' => 'Analysis cancelled')
    end

    it 'handles cancellation errors' do
      allow(mock_handler).to receive(:execute).and_return(
        Common::Result.failure(
          Common::Errors::BusinessError.new(message: 'Cannot cancel')
        )
      )

      post :cancel, params: { id: excel_file.id }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json).to include('success' => false, 'message' => 'Cannot cancel')
    end
  end

  describe 'GET #download' do
    before do
      allow(File).to receive(:exist?).with(excel_file.file_path).and_return(true)
      allow(controller).to receive(:send_file)
    end

    it 'sends file for download' do
      get :download, params: { id: excel_file.id }

      expect(controller).to have_received(:send_file).with(
        excel_file.file_path,
        filename: excel_file.original_name,
        type: 'application/octet-stream'
      )
    end

    it 'returns 404 when file does not exist' do
      allow(File).to receive(:exist?).with(excel_file.file_path).and_return(false)

      get :download, params: { id: excel_file.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  # FormulaEngine 분석 테스트 추가
  describe 'POST #analyze' do
    before do
      allow(ExcelAnalysis::Handlers::AnalyzeExcelHandler).to receive(:new).and_return(mock_analyze_handler)
    end

    let(:mock_analyze_handler) do
      instance_double(ExcelAnalysis::Handlers::AnalyzeExcelHandler,
        execute: Common::Result.success(
          message: 'Analysis completed',
          analysis_id: 123,
          errors_found: 5,
          ai_tier_used: 1,
          tokens_used: 100,
          formula_count: 15,
          formula_complexity_score: 2.5
        )
      )
    end

    it 'analyzes file with FormulaEngine integration' do
      post :analyze, params: { id: excel_file.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to include(
        'success' => true,
        'message' => 'Analysis completed',
        'analysis_id' => 123,
        'errors_found' => 5,
        'formula_count' => 15,
        'formula_complexity_score' => 2.5
      )
    end

    it 'handles analysis errors' do
      allow(mock_analyze_handler).to receive(:execute).and_return(
        Common::Result.failure(
          Common::Errors::BusinessError.new(message: 'Analysis failed')
        )
      )

      post :analyze, params: { id: excel_file.id }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json).to include('success' => false, 'error' => 'Analysis failed')
    end
  end

  describe 'GET #formula_analysis' do
    before do
      allow(ExcelAnalysis::Services::FormulaAnalysisService).to receive(:new).and_return(mock_formula_service)
    end

    let(:mock_formula_service) do
      instance_double(ExcelAnalysis::Services::FormulaAnalysisService,
        analyze: Common::Result.success(
          formula_count: 15,
          formula_complexity_score: 2.5,
          formula_functions: {
            total_functions: 25,
            unique_functions: 8,
            function_usage: [
              { name: 'SUM', count: 5 },
              { name: 'VLOOKUP', count: 3 }
            ]
          },
          formula_dependencies: { total_dependencies: 10 },
          circular_references: [],
          formula_errors: [
            { cell: 'A1', error_type: 'REF', message: 'Invalid reference' }
          ],
          formula_optimization_suggestions: [
            { type: 'complexity_reduction', priority: 'Medium' }
          ]
        )
      )
    end

    it 'returns formula analysis results' do
      get :formula_analysis, params: { id: excel_file.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json).to include(
        'success' => true,
        'file_id' => excel_file.id
      )

      formula_analysis = json['formula_analysis']
      expect(formula_analysis).to include(
        'formula_count' => 15,
        'complexity_score' => 2.5,
        'complexity_level' => 'Medium'
      )

      expect(formula_analysis).to have_key('function_statistics')
      expect(formula_analysis).to have_key('dependencies')
      expect(formula_analysis).to have_key('formula_errors')
      expect(formula_analysis).to have_key('optimization_suggestions')
      expect(formula_analysis).to have_key('summary')

      expect(formula_analysis['summary']).to include(
        'has_formulas' => true,
        'has_circular_references' => false,
        'has_formula_errors' => true,
        'needs_optimization' => true
      )
    end

    it 'handles formula analysis errors' do
      allow(mock_formula_service).to receive(:analyze).and_return(
        Common::Result.failure(
          Common::Errors::BusinessError.new(message: 'FormulaEngine unavailable')
        )
      )

      get :formula_analysis, params: { id: excel_file.id }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json).to include(
        'success' => false,
        'error' => 'FormulaEngine unavailable'
      )
    end
  end

  describe 'GET #analysis_status with formula analysis' do
    let(:analysis) do
      create(:analysis,
        excel_file: excel_file,
        user: user,
        formula_count: 20,
        formula_complexity_score: 3.2,
        formula_functions: {
          total_functions: 30,
          function_usage: [ { name: 'SUM', count: 10 } ]
        },
        circular_references: [ { cells: [ 'A1', 'B1' ] } ],
        formula_errors: [],
        formula_optimization_suggestions: []
      )
    end

    before do
      excel_file.analyses << analysis
    end

    it 'includes formula analysis in status response' do
      get :analysis_status, params: { id: excel_file.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      analysis_data = json['analysis']
      expect(analysis_data).to include('formula_analysis')

      formula_analysis = analysis_data['formula_analysis']
      expect(formula_analysis).to include(
        'formula_count' => 20,
        'complexity_score' => 3.2,
        'complexity_level' => 'High',
        'has_circular_references' => true,
        'circular_reference_count' => 1,
        'formula_error_count' => 0,
        'optimization_suggestion_count' => 0
      )
    end
  end
end
