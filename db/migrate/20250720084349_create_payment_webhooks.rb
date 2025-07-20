class CreatePaymentWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_webhooks do |t|
      t.string :event_type
      t.string :payment_key
      t.string :order_id
      t.string :status
      t.jsonb :payload, default: {}
      t.datetime :processed_at
      t.text :error_message

      t.timestamps
    end
    add_index :payment_webhooks, :event_type
    add_index :payment_webhooks, :payment_key
    add_index :payment_webhooks, :order_id
    add_index :payment_webhooks, :status
  end
end
