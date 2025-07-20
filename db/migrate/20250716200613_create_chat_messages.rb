class CreateChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_messages do |t|
      t.references :chat_conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false
      t.string :role, null: false, default: 'user'
      t.json :metadata
      t.integer :credits_used, default: 0

      t.timestamps
    end

    add_index :chat_messages, :role
    add_index :chat_messages, :created_at
  end
end
