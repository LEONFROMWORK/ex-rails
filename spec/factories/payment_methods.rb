FactoryBot.define do
  factory :payment_method do
    user { nil }
    method_type { "MyString" }
    is_default { false }
    card_number { "MyString" }
    card_type { "MyString" }
    billing_key_id { nil }
    metadata { "" }
  end
end
