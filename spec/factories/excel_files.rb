# frozen_string_literal: true

FactoryBot.define do
  factory :excel_file do
    association :user
    sequence(:original_name) { |n| "test_file_#{n}.xlsx" }
    file_path { Rails.root.join('spec', 'fixtures', 'test.xlsx').to_s }
    file_size { 1024 }
    content_hash { SecureRandom.hex(32) }
    status { :uploaded }

    trait :analyzed do
      status { :analyzed }
    end

    trait :failed do
      status { :failed }
      error_message { "Processing failed" }
    end
  end
end
