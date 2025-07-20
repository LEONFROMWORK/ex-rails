FactoryBot.define do
  factory :payment_webhook do
    event_type { "MyString" }
    payment_key { "MyString" }
    order_id { "MyString" }
    status { "MyString" }
    payload { "" }
    processed_at { "2025-07-20 17:43:49" }
    error_message { "MyText" }
  end
end
