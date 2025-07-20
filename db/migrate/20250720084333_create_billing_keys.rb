class CreateBillingKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :billing_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :billing_key
      t.string :customer_key
      t.string :card_number
      t.string :card_type
      t.string :card_owner_type
      t.string :issuer_code
      t.string :acquirer_code

      t.timestamps
    end
    add_index :billing_keys, :billing_key, unique: true
    add_index :billing_keys, :customer_key, unique: true
  end
end
