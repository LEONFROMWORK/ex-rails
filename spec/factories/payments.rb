FactoryBot.define do
  factory :payment do
    user { nil }
    transaction_id { "MyString" }
    order_id { "MyString" }
    payment_method { "card" }
    amount { 1 }
    currency { "MyString" }
    status { "MyString" }
    approved_at { "2025-07-20 17:43:03" }
    canceled_at { "2025-07-20 17:43:03" }
    failed_at { "2025-07-20 17:43:03" }
    card_number { "MyString" }
    card_type { "MyString" }
    receipt_url { "MyString" }
    checkout_url { "MyString" }
    failure_code { "MyString" }
    failure_message { "MyString" }
    metadata { "" }
  end
end
