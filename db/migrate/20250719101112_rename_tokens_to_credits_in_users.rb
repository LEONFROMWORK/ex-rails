class RenameTokensToCreditsInUsers < ActiveRecord::Migration[8.0]
  def change
    # Rename tokens column to credits in users table
    rename_column :users, :credits, :credits

    # Update index name if it exists
    if index_exists?(:users, :credits, name: 'index_users_on_tokens')
      rename_index :users, 'index_users_on_tokens', 'index_users_on_credits'
    end

    # Rename related columns in other tables
    if column_exists?(:payment_intents, :credits)
      rename_column :payment_intents, :credits, :credits
    end

    if column_exists?(:analyses, :credits_used)
      rename_column :analyses, :credits_used, :credits_used
    end

    if column_exists?(:ai_usage_records, :input_tokens)
      rename_column :ai_usage_records, :input_tokens, :input_credits
    end

    if column_exists?(:ai_usage_records, :output_tokens)
      rename_column :ai_usage_records, :output_tokens, :output_credits
    end

    if column_exists?(:rag_documents, :credits)
      rename_column :rag_documents, :credits, :credits
    end
  end
end
