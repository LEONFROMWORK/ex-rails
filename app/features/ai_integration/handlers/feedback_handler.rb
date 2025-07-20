# frozen_string_literal: true

module AiIntegration
  module Handlers
    class FeedbackHandler < Common::BaseHandler
      def initialize(user:, conversation_id:, message_id:, rating:, feedback_text: nil)
        @user = user
        @conversation_id = conversation_id
        @message_id = message_id
        @rating = rating
        @feedback_text = feedback_text
      end

      def execute
        return failure("Invalid rating") unless valid_rating?

        conversation = find_conversation
        return failure("Conversation not found") unless conversation

        message = find_message(conversation)
        return failure("Message not found") unless message

        save_feedback(message)
        update_ai_metrics(message)

        success({ message: "Feedback saved successfully" })
      end

      private

      attr_reader :user, :conversation_id, :message_id, :rating, :feedback_text

      def valid_rating?
        @rating.is_a?(Integer) && @rating.between?(1, 5)
      end

      def find_conversation
        @user.chat_conversations.find_by(id: @conversation_id)
      end

      def find_message(conversation)
        conversation.chat_messages.find_by(id: @message_id, role: "assistant")
      end

      def save_feedback(message)
        message.update!(
          user_rating: @rating,
          user_feedback: @feedback_text
        )

        # Also create a separate feedback record for analytics
        AiFeedback.create!(
          user: @user,
          chat_message: message,
          rating: @rating,
          feedback_text: @feedback_text,
          ai_tier_used: message.ai_tier_used,
          provider: message.provider,
          confidence_score: message.confidence_score
        )
      end

      def update_ai_metrics(message)
        # Update provider performance metrics
        provider_name = message.provider&.split("/")&.first
        return unless provider_name

        metric = AiProviderMetric.find_or_initialize_by(
          provider: provider_name,
          model: message.provider,
          tier: message.ai_tier_used
        )

        metric.total_requests += 1
        metric.total_rating += @rating
        metric.average_rating = metric.total_rating.to_f / metric.total_requests

        if @rating >= 4
          metric.positive_feedback_count += 1
        elsif @rating <= 2
          metric.negative_feedback_count += 1
        end

        metric.save!
      end
    end
  end
end
