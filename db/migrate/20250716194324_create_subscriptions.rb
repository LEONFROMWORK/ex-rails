class CreateSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :plan_type, null: false
      t.integer :status, default: 0, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.datetime :canceled_at
      t.string :payment_id
      t.string :payment_method
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency, default: 'KRW'
      t.json :metadata

      t.timestamps
    end

    add_index :subscriptions, :status
    add_index :subscriptions, :plan_type
    add_index :subscriptions, [ :user_id, :status ]
    add_index :subscriptions, :ends_at
  end
end
