# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API Integration Tests', type: :request, vcr: true do
  let(:user) { create(:user, credits: 100) }
  let(:admin) { create(:user, role: 'admin') }

  before do
    sign_in user
  end

  describe 'Excel File API' do
    describe 'POST /excel_files' do
      let(:file) { fixture_file_upload('sample.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') }

      it 'uploads excel file successfully' do
        post excel_files_path, params: { excel_file: { file: file } }

        expect(response).to have_http_status(:created)
        expect(response.parsed_body['success']).to be true
        expect(ExcelFile.count).to eq(1)
      end

      it 'rejects non-excel files' do
        txt_file = fixture_file_upload('sample.txt', 'text/plain')

        post excel_files_path, params: { excel_file: { file: txt_file } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('Invalid file format')
      end

      it 'rejects files exceeding size limit' do
        allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:size).and_return(11.megabytes)

        post excel_files_path, params: { excel_file: { file: file } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('File too large')
      end
    end

    describe 'POST /excel_files/:id/analyze' do
      let(:excel_file) { create(:excel_file, user: user, status: 'uploaded') }

      it 'starts analysis with valid parameters' do
        post analyze_excel_file_path(excel_file), params: {
          ai_tier: 1,
          custom_prompt: 'Analyze the data structure'
        }

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body['message']).to include('Analysis started')
      end

      it 'rejects analysis with insufficient tokens' do
        user.update!(credits: 1)

        post analyze_excel_file_path(excel_file), params: { ai_tier: 1 }

        expect(response).to have_http_status(:payment_required)
        expect(response.parsed_body['error']).to include('Insufficient tokens')
      end

      it 'rejects tier 2 analysis for free users' do
        user.update!(tier: 'free')

        post analyze_excel_file_path(excel_file), params: { ai_tier: 2 }

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to include('Upgrade required')
      end
    end

    describe 'GET /excel_files/:id' do
      let(:excel_file) { create(:excel_file, user: user) }
      let!(:analysis) { create(:analysis, excel_file: excel_file) }

      it 'returns file details with analysis' do
        get excel_file_path(excel_file)

        expect(response).to have_http_status(:ok)
        data = response.parsed_body

        expect(data['excel_file']['id']).to eq(excel_file.id)
        expect(data['analysis']).to be_present
        expect(data['analysis']['insights']).to be_present
      end

      it 'prevents access to other users files' do
        other_user = create(:user)
        other_file = create(:excel_file, user: other_user)

        get excel_file_path(other_file)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'Chat API' do
    let(:excel_file) { create(:excel_file, user: user, status: 'analyzed') }
    let!(:analysis) { create(:analysis, excel_file: excel_file) }

    describe 'POST /excel_files/:id/chat' do
      it 'creates chat message and generates response' do
        post chat_excel_file_path(excel_file), params: {
          message: 'What are the main insights from this data?'
        }

        expect(response).to have_http_status(:ok)
        data = response.parsed_body

        expect(data['user_message']).to eq('What are the main insights from this data?')
        expect(data['ai_response']).to be_present
        expect(data['conversation_id']).to be_present
      end

      it 'maintains conversation context' do
        conversation = create(:chat_conversation, user: user, excel_file: excel_file)

        post chat_excel_file_path(excel_file), params: {
          message: 'Tell me more about that',
          conversation_id: conversation.id
        }

        expect(response).to have_http_status(:ok)
        expect(conversation.reload.messages.count).to be >= 2
      end

      it 'consumes tokens for chat' do
        expect {
          post chat_excel_file_path(excel_file), params: {
            message: 'What are the main insights from this data?'
          }
        }.to change { user.reload.credits }.by(-2)
      end
    end
  end

  describe 'Template Generation API' do
    describe 'POST /templates/generate' do
      it 'generates excel template successfully' do
        post generate_templates_path, params: {
          template_type: 'financial_report',
          rows: 100,
          columns: 10,
          custom_fields: [ 'Revenue', 'Expenses', 'Profit' ]
        }

        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Type']).to include('application/vnd.openxmlformats')
        expect(response.headers['Content-Disposition']).to include('financial_report_template.xlsx')
      end

      it 'handles invalid template parameters' do
        post generate_templates_path, params: {
          template_type: 'invalid_type',
          rows: -1
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors']).to be_present
      end
    end
  end

  describe 'Payment API' do
    describe 'POST /payments/create_intent' do
      it 'creates payment intent for token purchase' do
        post create_intent_payments_path, params: {
          package: 'basic',
          credits: 100,
          amount: 10000
        }

        expect(response).to have_http_status(:ok)
        data = response.parsed_body

        expect(data['payment_intent_id']).to be_present
        expect(data['client_key']).to be_present
        expect(data['amount']).to eq(10000)
      end

      it 'validates payment parameters' do
        post create_intent_payments_path, params: {
          package: 'invalid',
          credits: -1
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors']).to be_present
      end
    end

    describe 'POST /payments/confirm' do
      let(:payment_intent) { create(:payment_intent, user: user, amount: 10000, credits: 100) }

      it 'confirms successful payment and adds tokens' do
        post confirm_payments_path, params: {
          payment_intent_id: payment_intent.toss_payment_key,
          order_id: payment_intent.order_id
        }

        expect(response).to have_http_status(:ok)
        expect(user.reload.credits).to eq(200) # Original 100 + purchased 100
        expect(payment_intent.reload.status).to eq('completed')
      end
    end
  end

  describe 'Admin API' do
    before { sign_in admin }

    describe 'GET /admin/dashboard' do
      it 'returns admin dashboard data' do
        create_list(:user, 5)
        create_list(:excel_file, 10)

        get admin_dashboard_path

        expect(response).to have_http_status(:ok)
        data = response.parsed_body

        expect(data['users_count']).to eq(6) # 5 created + admin
        expect(data['files_count']).to eq(10)
        expect(data['recent_activities']).to be_present
      end
    end

    describe 'GET /admin/system_status' do
      it 'returns system health metrics' do
        get admin_system_status_path

        expect(response).to have_http_status(:ok)
        data = response.parsed_body

        expect(data['database_status']).to eq('healthy')
        expect(data['queue_status']).to be_present
        expect(data['memory_usage']).to be_present
      end
    end
  end

  describe 'Error Handling' do
    it 'handles 404 errors gracefully' do
      get '/non_existent_path'

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('Not Found')
    end

    it 'handles unauthorized access' do
      sign_out user

      get excel_files_path

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to include('authentication required')
    end

    it 'handles internal server errors' do
      allow_any_instance_of(ExcelFilesController).to receive(:index).and_raise(StandardError, 'Test error')

      get excel_files_path

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body['error']).to include('Internal server error')
    end
  end

  describe 'Rate Limiting' do
    it 'enforces API rate limits' do
      11.times do
        post excel_files_path, params: { excel_file: { file: fixture_file_upload('sample.xlsx') } }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to include('Rate limit exceeded')
    end
  end
end
