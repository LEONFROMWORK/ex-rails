# frozen_string_literal: true

module AiIntegration
  module Jobs
    class ProcessChatMessageJob < ApplicationJob
      queue_as :ai_analysis

      def perform(conversation_id:, message_id:)
        conversation = ChatConversation.find(conversation_id)
        message = ChatMessage.find(message_id)

        # Build context from conversation history
        context = build_conversation_context(conversation)

        # Determine AI provider and model
        ai_service = AiIntegration::MultiProvider::ChatService.new(
          provider: determine_provider(conversation.user)
        )

        # Generate AI response
        result = ai_service.generate_response(
          message: message.content,
          context: context,
          file_context: conversation.excel_file&.metadata
        )

        if result.success?
          response_data = result.value

          # Create assistant message
          assistant_message = conversation.messages.create!(
            user: conversation.user,
            content: response_data[:content],
            role: "assistant",
            credits_used: response_data[:credits_used],
            metadata: {
              model: response_data[:model],
              provider: ai_service.provider
            }
          )

          # Deduct tokens
          conversation.user.consume_tokens!(response_data[:credits_used])

          # Broadcast response
          broadcast_message(conversation, assistant_message)
        else
          broadcast_error(conversation, result.error)
        end
      rescue StandardError => e
        Rails.logger.error("Chat message processing failed: #{e.message}")
        broadcast_error(conversation, "Failed to generate response")
        raise
      end

      private

      def build_conversation_context(conversation)
        # Get last 10 messages for context
        recent_messages = conversation.messages
                                    .order(created_at: :desc)
                                    .limit(10)
                                    .reverse

        recent_messages.map do |msg|
          { role: msg.role, content: msg.content }
        end
      end

      def determine_provider(user)
        # Use more advanced models for pro users
        user.pro? || user.enterprise? ? "anthropic" : "openai"
      end

      def broadcast_message(conversation, message)
        ActionCable.server.broadcast(
          "chat_conversation_#{conversation.id}",
          {
            type: "new_message",
            message: {
              id: message.id,
              content: message.content,
              role: message.role,
              created_at: message.created_at,
              credits_used: message.credits_used
            }
          }
        )
      end

      def broadcast_error(conversation, error_message)
        ActionCable.server.broadcast(
          "chat_conversation_#{conversation.id}",
          {
            type: "error",
            error: error_message
          }
        )
      end
    end
  end
end
