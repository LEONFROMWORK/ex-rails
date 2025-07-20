# frozen_string_literal: true

class CreateAiUsageRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_usage_records do |t|
      t.references :user, null: true, foreign_key: true
      t.string :model_id, null: false
      t.integer :provider, null: false, default: 0
      t.decimal :cost, precision: 10, scale: 6, null: false, default: 0.0
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :request_type, null: false, default: 0
      t.text :request_prompt, null: true
      t.text :response_content, null: true
      t.json :metadata, null: true
      t.decimal :latency_ms, precision: 10, scale: 2, null: true
      t.string :request_id, null: true
      t.string :session_id, null: true

      t.timestamps
    end

    add_index :ai_usage_records, :user_id, if_not_exists: true
    add_index :ai_usage_records, :model_id, if_not_exists: true
    add_index :ai_usage_records, :provider, if_not_exists: true
    add_index :ai_usage_records, :request_type, if_not_exists: true
    add_index :ai_usage_records, :created_at, if_not_exists: true
    add_index :ai_usage_records, [ :user_id, :created_at ], if_not_exists: true
    add_index :ai_usage_records, [ :provider, :created_at ], if_not_exists: true
    add_index :ai_usage_records, [ :model_id, :created_at ], if_not_exists: true
    add_index :ai_usage_records, :session_id, if_not_exists: true
    add_index :ai_usage_records, :request_id, if_not_exists: true
  end
end
