class CreatePaymentIntents < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_intents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :order_id, null: false, index: { unique: true }
      t.integer :amount, null: false
      t.string :payment_type, null: false
      t.string :status, null: false, default: 'created'
      t.string :toss_payment_key
      t.string :toss_transaction_id
      t.text :error_message
      t.datetime :paid_at
      t.json :metadata

      t.timestamps
    end

    add_index :payment_intents, :status
    add_index :payment_intents, :payment_type
    add_index :payment_intents, :toss_payment_key
  end
end
