class CreateChatConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :excel_file, foreign_key: true
      t.string :title
      t.integer :status, default: 0, null: false
      t.json :context
      t.integer :message_count, default: 0
      t.integer :total_tokens_used, default: 0

      t.timestamps
    end

    add_index :chat_conversations, :status
    add_index :chat_conversations, :created_at
  end
end
