class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.references :user, null: false, foreign_key: true
      t.string :transaction_id
      t.string :order_id
      t.string :payment_method
      t.integer :amount
      t.string :currency
      t.string :status
      t.datetime :approved_at
      t.datetime :canceled_at
      t.datetime :failed_at
      t.string :card_number
      t.string :card_type
      t.string :receipt_url
      t.string :checkout_url
      t.string :failure_code
      t.string :failure_message
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    add_index :payments, :transaction_id, unique: true
    add_index :payments, :order_id, unique: true
    add_index :payments, :status
    add_index :payments, :payment_method
  end
end
