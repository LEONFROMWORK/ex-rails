# frozen_string_literal: true

class ChatConversationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation, only: [ :show, :send_message ]

  def index
    @conversations = current_user.chat_conversations.recent.page(params[:page])
    @new_conversation = current_user.chat_conversations.build
  end

  def show
    @messages = @conversation.messages.order(created_at: :asc)
    @new_message = @conversation.messages.build
  end

  def create
    @conversation = current_user.chat_conversations.build(conversation_params)

    if @conversation.save
      redirect_to @conversation, notice: "New conversation started"
    else
      redirect_to chat_conversations_path, alert: "Failed to create conversation"
    end
  end

  def send_message
    # Check user tokens
    if current_user.credits < 5
      render json: { error: "Insufficient tokens. You need at least 5 tokens to send a message." },
             status: :payment_required
      return
    end

    # Create message record
    message = @conversation.messages.create!(
      user: current_user,
      content: params[:message],
      role: "user"
    )

    # Queue AI response
    AiIntegration::Jobs::ProcessChatMessageJob.perform_later(
      conversation_id: @conversation.id,
      message_id: message.id
    )

    render json: {
      message: message.as_json,
      status: "queued"
    }
  end

  private

  def set_conversation
    @conversation = current_user.chat_conversations.find(params[:id])
  end

  def conversation_params
    params.require(:chat_conversation).permit(:title, :excel_file_id)
  end
end
