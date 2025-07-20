# frozen_string_literal: true

FactoryBot.define do
  factory :chat_conversation do
    association :user
    association :excel_file
    title { "Chat about #{excel_file&.original_name || 'Excel file'}" }

    trait :with_messages do
      after(:create) do |conversation|
        create_list(:chat_message, 3, conversation: conversation)
      end
    end
  end

  factory :chat_message do
    association :conversation, factory: :chat_conversation
    content { "What are the key insights from this data?" }
    role { :user }

    trait :ai_response do
      role { :ai }
      content { "Based on the analysis, here are the key insights..." }
    end
  end
end
