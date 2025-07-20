class CreatePaymentMethods < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_methods do |t|
      t.references :user, null: false, foreign_key: true
      t.string :method_type
      t.boolean :is_default, default: false
      t.string :card_number
      t.string :card_type
      t.references :billing_key, foreign_key: true
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    add_index :payment_methods, :method_type
  end
end
