# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }
    password_confirmation { "password123" }
    credits { 100 }
    tier { :free }
    role { :user }
    email_verified { true }

    trait :admin do
      role { :admin }
    end

    trait :pro do
      tier { :pro }
      credits { 500 }
    end

    trait :enterprise do
      tier { :enterprise }
      credits { 1000 }
    end

    trait :with_subscription do
      after(:create) do |user|
        create(:subscription, user: user)
      end
    end

    trait :low_credits do
      credits { 5 }
    end

    trait :no_credits do
      credits { 0 }
    end
  end
end
