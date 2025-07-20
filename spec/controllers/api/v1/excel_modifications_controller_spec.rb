# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::ExcelModificationsController, type: :controller do
  let(:user) { create(:user, credits: 500) }
  let(:excel_file) { create(:excel_file, user: user) }

  before do
    sign_in(user)
  end

  describe 'POST #modify' do
    let(:valid_params) do
      {
        file_id: excel_file.id,
        screenshot: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
        request: "A1에 합계 공식을 추가해주세요"
      }
    end

    context 'with valid parameters' do
      before do
        allow_any_instance_of(ExcelModification::Handlers::ModifyExcelHandler)
          .to receive(:execute)
          .and_return(
            Common::Result.success({
              modified_file: create(:excel_file, user: user),
              modifications: [ { 'cell' => 'A1', 'formula' => '=SUM(B1:B10)' } ],
              download_url: '/download/123',
              preview: { filename: 'modified.xlsx' },
              credits_used: 50
            })
          )
      end

      it 'returns success response' do
        post :modify, params: valid_params

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['modifications']).to be_present
        expect(json['data']['download_url']).to eq('/download/123')
      end
    end

    context 'with missing screenshot' do
      it 'returns bad request' do
        post :modify, params: valid_params.except(:screenshot)

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('screenshot')
      end
    end

    context 'with non-existent file' do
      it 'returns not found' do
        post :modify, params: valid_params.merge(file_id: 999999)

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end
  end

  describe 'POST #convert_to_formula' do
    let(:valid_params) do
      {
        text: "A1부터 A10까지 합계",
        worksheet: "Sheet1",
        cell: "B1",
        range: "A1:A10"
      }
    end

    context 'with valid parameters' do
      before do
        allow_any_instance_of(ExcelModification::Services::AiToFormulaConverter)
          .to receive(:convert)
          .and_return(
            Common::Result.success({
              formula: '=SUM(A1:A10)',
              explanation: '합계 공식',
              cell_reference: 'B1'
            })
          )
      end

      it 'returns converted formula' do
        post :convert_to_formula, params: valid_params

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['formula']).to eq('=SUM(A1:A10)')
      end
    end

    context 'with conversion failure' do
      before do
        allow_any_instance_of(ExcelModification::Services::AiToFormulaConverter)
          .to receive(:convert)
          .and_return(Common::Result.failure("Conversion failed"))
      end

      it 'returns error response' do
        post :convert_to_formula, params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end
  end
end
