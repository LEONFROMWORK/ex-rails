# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Excel Modification Flow', type: :request do
  let(:user) { create(:user, credits: 1000) }
  let(:excel_file) { create(:excel_file, user: user) }
  let(:headers) do
    {
      'Content-Type' => 'application/json'
    }
  end

  let(:valid_screenshot) { "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" }

  before do
    # Mock authentication
    allow_any_instance_of(Api::V1::BaseController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Api::V1::BaseController).to receive(:current_user).and_return(user)
    # Mock system services
    allow(User).to receive(:system_user).and_return(user)

    # Mock FormulaEngineClient
    allow(FormulaEngineClient).to receive(:instance).and_return(
      instance_double('FormulaEngineClient')
    )
    allow(FormulaEngineClient).to receive(:validate_formula).and_return(
      Common::Result.success(valid: true, errors: [])
    )

    # Mock multimodal service
    multimodal_service = instance_double('AiIntegration::Services::MultimodalCoordinatorService')
    allow(AiIntegration::Services::MultimodalCoordinatorService).to receive(:new).and_return(multimodal_service)

    # Mock successful AI analysis
    allow(multimodal_service).to receive(:analyze_image).and_return(
      Common::Result.success({
        formula: '=SUM(A1:A10)',
        explanation: '요청하신 합계 공식입니다',
        confidence: 0.95,
        modifications: [
          {
            'type' => 'formula',
            'cell' => 'B1',
            'value' => '=SUM(A1:A10)',
            'description' => 'A1부터 A10까지의 합계'
          }
        ]
      })
    )

    # Mock Excel file operations
    allow_any_instance_of(ExcelModification::Services::ExcelModificationService).to receive(:apply_modifications).and_return(
      Common::Result.success({
        modified_file_path: Rails.root.join('tmp', 'modified_test.xlsx'),
        modifications_count: 1
      })
    )

    # Mock the entire modify_with_ai_suggestions method
    modified_file = create(:excel_file, user: user, original_name: 'modified_test.xlsx')
    allow_any_instance_of(ExcelModification::Services::ExcelModificationService).to receive(:modify_with_ai_suggestions).and_return(
      Common::Result.success({
        modified_file: modified_file,
        modifications_applied: [
          { 'cell' => 'B1', 'value' => '=SUM(A1:A10)', 'description' => 'A1부터 A10까지의 합계' }
        ],
        download_url: "/download/#{modified_file.id}",
        preview: { filename: 'modified_test.xlsx' }
      })
    )
  end

  describe 'POST /api/v1/excel_modifications/modify' do
    let(:valid_params) do
      {
        file_id: excel_file.id,
        screenshot: valid_screenshot,
        request: 'A1부터 A10까지 합계를 구하는 공식을 B1에 넣어주세요'
      }
    end

    context '정상적인 요청' do
      it 'Excel 파일이 성공적으로 수정됨' do
        post '/api/v1/excel_modifications/modify',
             params: valid_params.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['data']).to include(
          'modified_file',
          'modifications',
          'download_url',
          'credits_used'
        )

        # 수정 내역 확인
        modifications = json_response['data']['modifications']
        expect(modifications).to be_an(Array)
        expect(modifications.first).to include(
          'cell' => 'B1',
          'value' => '=SUM(A1:A10)'
        )

        # 크레딧 차감 확인
        credits_used = json_response['data']['credits_used']
        expect(credits_used).to be > 0
        user.reload
        expect(user.credits).to eq(1000 - credits_used)
      end
    end

    context '스크린샷 없이 요청' do
      it '400 Bad Request 응답' do
        post '/api/v1/excel_modifications/modify',
             params: valid_params.except(:screenshot).to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('screenshot')
      end
    end

    context '요청 내용 없이 전송' do
      it '400 Bad Request 응답' do
        # Mock validation error
        allow_any_instance_of(ExcelModification::Handlers::ModifyExcelHandler).to receive(:execute).and_return(
          Common::Result.failure(
            CommonErrors::ValidationError.new(
              message: "User request cannot be blank",
              details: { errors: [ "User request cannot be blank" ] }
            )
          )
        )

        post '/api/v1/excel_modifications/modify',
             params: valid_params.merge(request: '').to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('request')
      end
    end

    context '다른 사용자의 파일 접근 시도' do
      let(:other_user) { create(:user) }
      let(:other_file) { create(:excel_file, user: other_user) }

      it '404 Not Found 응답' do
        post '/api/v1/excel_modifications/modify',
             params: valid_params.merge(file_id: other_file.id).to_json,
             headers: headers

        expect(response).to have_http_status(:not_found)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('not found')
      end
    end

    context '크레딧 부족' do
      before do
        user.update!(credits: 10)

        # Mock insufficient credits error
        allow_any_instance_of(ExcelModification::Handlers::ModifyExcelHandler).to receive(:execute).and_return(
          Common::Result.failure(
            CommonErrors::InsufficientCreditsError.new(
              required: 50,
              available: 10
            )
          )
        )
      end

      it '402 Payment Required 응답' do
        post '/api/v1/excel_modifications/modify',
             params: valid_params.to_json,
             headers: headers

        expect(response).to have_http_status(:payment_required)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('credits')
        expect(json_response['details']).to include(
          'required' => 50,
          'available' => 10
        )
      end
    end
  end

  describe 'POST /api/v1/excel_modifications/convert_to_formula' do
    let(:valid_params) do
      {
        text: 'A1부터 A10까지 합계',
        worksheet: 'Sheet1',
        cell: 'B1'
      }
    end

    context '정상적인 변환 요청' do
      before do
        allow_any_instance_of(ExcelModification::Services::AiToFormulaConverter).to receive(:convert).and_return(
          Common::Result.success({
            formula: '=SUM(A1:A10)',
            explanation: 'A1부터 A10까지의 합계를 계산합니다',
            cell_reference: 'B1'
          })
        )
      end

      it '공식이 성공적으로 변환됨' do
        post '/api/v1/excel_modifications/convert_to_formula',
             params: valid_params.to_json,
             headers: headers

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['data']).to include(
          'formula' => '=SUM(A1:A10)',
          'explanation' => 'A1부터 A10까지의 합계를 계산합니다',
          'cell_reference' => 'B1'
        )
      end
    end

    context '빈 텍스트로 요청' do
      it '422 Unprocessable Entity 응답' do
        post '/api/v1/excel_modifications/convert_to_formula',
             params: valid_params.merge(text: '').to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)

        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
      end
    end
  end

  describe '전체 시나리오 테스트' do
    it '사용자가 Excel 파일을 수정하는 전체 플로우' do
      # 수정 요청
      post '/api/v1/excel_modifications/modify',
           params: {
             file_id: excel_file.id,
             screenshot: valid_screenshot,
             request: 'A1부터 A10까지 합계를 B1에 표시해주세요'
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be true

      # 수정된 파일 다운로드 URL 확인
      download_url = json_response['data']['download_url']
      expect(download_url).to be_present

      # 크레딧 차감 확인
      credits_used = json_response['data']['credits_used']
      user.reload
      expect(user.credits).to eq(1000 - credits_used)
    end
  end
end
