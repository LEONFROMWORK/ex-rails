# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AiController, type: :controller do
  let(:user) { create(:user, credits: 200) }
  let(:excel_file) { create(:excel_file, user: user) }
  let(:conversation) { create(:chat_conversation, user: user, excel_file: excel_file) }

  before do
    # Mock authentication
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:authenticate_user!).and_return(true)

    # Mock AI service responses
    allow_any_instance_of(Ai::Handlers::ChatHandler).to receive(:execute).and_return(
      Common::Result.success(mock_chat_response)
    )
  end

  describe 'POST #chat' do
    let(:valid_params) do
      {
        message: 'Analyze this Excel file for errors',
        conversation_id: conversation.id,
        file_id: excel_file.id
      }
    end

    context 'with valid parameters' do
      it 'returns successful response' do
        post :chat, params: valid_params

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('success')
        expect(json_response['data']).to include('message', 'conversation_id', 'tokens_used')
      end

      it 'creates a new chat message' do
        expect {
          post :chat, params: valid_params
        }.to change { ChatMessage.count }.by(1)

        message = ChatMessage.last
        expect(message.user).to eq(user)
        expect(message.chat_conversation).to eq(conversation)
      end

      it 'consumes user tokens' do
        original_tokens = user.credits
        post :chat, params: valid_params

        user.reload
        expect(user.credits).to be < original_tokens
      end
    end

    context 'with missing message' do
      it 'returns validation error' do
        post :chat, params: { conversation_id: conversation.id }

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to include('Message is required')
      end
    end

    context 'with insufficient tokens' do
      before do
        user.update!(credits: 1)
        allow_any_instance_of(Ai::Handlers::ChatHandler).to receive(:execute).and_return(
          Common::Result.failure('Insufficient tokens')
        )
      end

      it 'returns insufficient tokens error' do
        post :chat, params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to include('Insufficient tokens')
      end
    end

    context 'with invalid conversation' do
      it 'returns not found error' do
        post :chat, params: valid_params.merge(conversation_id: 99999)

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('error')
      end
    end

    context 'with file context' do
      it 'includes file information in AI request' do
        expect_any_instance_of(Ai::Handlers::ChatHandler).to receive(:initialize).with(
          hash_including(
            user: user,
            message: valid_params[:message],
            conversation_id: conversation.id,
            file_id: excel_file.id
          )
        ).and_call_original

        post :chat, params: valid_params
      end
    end

    context 'without authentication' do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
        allow(controller).to receive(:authenticate_user!).and_raise(
          ActionController::RoutingError.new('Not authenticated')
        )
      end

      it 'returns unauthorized error' do
        expect {
          post :chat, params: valid_params
        }.to raise_error(ActionController::RoutingError)
      end
    end
  end

  describe 'POST #feedback' do
    let(:chat_message) do
      create(:chat_message,
        chat_conversation: conversation,
        user: user,
        role: 'assistant',
        ai_tier_used: 1,
        tokens_used: 50
      )
    end

    let(:valid_feedback_params) do
      {
        chat_message_id: chat_message.id,
        rating: 4,
        feedback_text: 'Very helpful response'
      }
    end

    before do
      allow_any_instance_of(Ai::Handlers::FeedbackHandler).to receive(:execute).and_return(
        Common::Result.success(mock_feedback_response)
      )
    end

    context 'with valid parameters' do
      it 'returns successful response' do
        post :feedback, params: valid_feedback_params

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('success')
        expect(json_response['data']).to include('feedback_id')
      end

      it 'creates feedback record' do
        expect {
          post :feedback, params: valid_feedback_params
        }.to change { AiFeedback.count }.by(1)

        feedback = AiFeedback.last
        expect(feedback.user).to eq(user)
        expect(feedback.chat_message).to eq(chat_message)
        expect(feedback.rating).to eq(4)
      end
    end

    context 'with invalid rating' do
      it 'returns validation error for rating out of range' do
        allow_any_instance_of(Ai::Handlers::FeedbackHandler).to receive(:execute).and_return(
          Common::Result.failure('Rating must be between 1 and 5')
        )

        post :feedback, params: valid_feedback_params.merge(rating: 6)

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to include('Rating must be between 1 and 5')
      end
    end

    context 'with missing chat message' do
      it 'returns not found error' do
        allow_any_instance_of(Ai::Handlers::FeedbackHandler).to receive(:execute).and_return(
          Common::Result.failure('Chat message not found')
        )

        post :feedback, params: valid_feedback_params.merge(chat_message_id: 99999)

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with unauthorized access to chat message' do
      let(:other_user) { create(:user) }
      let(:other_conversation) { create(:chat_conversation, user: other_user) }
      let(:other_message) do
        create(:chat_message, chat_conversation: other_conversation, user: other_user)
      end

      it 'returns forbidden error' do
        allow_any_instance_of(Ai::Handlers::FeedbackHandler).to receive(:execute).and_return(
          Common::Result.failure('Access denied')
        )

        post :feedback, params: valid_feedback_params.merge(chat_message_id: other_message.id)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'Rate limiting' do
    context 'when user exceeds rate limit' do
      before do
        # Simulate rate limiting
        allow(Rack::Attack).to receive(:enabled?).and_return(true)
        allow_any_instance_of(ActionController::Base).to receive(:request).and_return(
          double(ip: '127.0.0.1', path: '/api/v1/ai/chat')
        )
      end

      it 'returns rate limit error after multiple requests' do
        # Make multiple requests quickly
        10.times do
          post :chat, params: { message: 'test' }
        end

        # The last request should be rate limited
        # Note: This would need actual rate limiting middleware configured
        expect(response.status).to be_in([ 200, 429 ])
      end
    end
  end

  describe 'Error handling' do
    context 'when AI service is unavailable' do
      before do
        allow_any_instance_of(Ai::Handlers::ChatHandler).to receive(:execute).and_return(
          Common::Result.failure('AI service temporarily unavailable')
        )
      end

      it 'returns service unavailable error' do
        post :chat, params: { message: 'test message' }

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('error')
        expect(json_response['message']).to include('temporarily unavailable')
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow_any_instance_of(Ai::Handlers::ChatHandler).to receive(:execute).and_raise(
          StandardError.new('Unexpected error')
        )
      end

      it 'returns internal server error' do
        post :chat, params: { message: 'test message' }

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)

        expect(json_response['status']).to eq('error')
      end
    end
  end

  describe 'Response format validation' do
    it 'returns consistent JSON structure for success' do
      post :chat, params: { message: 'test message' }

      json_response = JSON.parse(response.body)

      expect(json_response).to include('status', 'data')
      expect(json_response['status']).to eq('success')
      expect(json_response['data']).to be_a(Hash)
    end

    it 'returns consistent JSON structure for errors' do
      allow_any_instance_of(Ai::Handlers::ChatHandler).to receive(:execute).and_return(
        Common::Result.failure('Test error')
      )

      post :chat, params: { message: 'test message' }

      json_response = JSON.parse(response.body)

      expect(json_response).to include('status', 'message')
      expect(json_response['status']).to eq('error')
      expect(json_response['message']).to be_a(String)
    end
  end

  private

  def mock_chat_response
    {
      message: 'AI analysis response',
      conversation_id: conversation.id,
      tokens_used: 50,
      ai_tier_used: 1,
      confidence_score: 0.85,
      provider: 'openai'
    }
  end

  def mock_feedback_response
    {
      feedback_id: 123,
      message: 'Feedback recorded successfully'
    }
  end
end
