FactoryBot.define do
  factory :billing_key do
    user { nil }
    billing_key { "MyString" }
    customer_key { "MyString" }
    card_number { "MyString" }
    card_type { "MyString" }
    card_owner_type { "MyString" }
    issuer_code { "MyString" }
    acquirer_code { "MyString" }
    created_at { "2025-07-20 17:43:33" }
  end
end
