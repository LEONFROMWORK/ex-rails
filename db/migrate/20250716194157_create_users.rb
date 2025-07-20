class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.integer :role, default: 0, null: false
      t.integer :tier, default: 0, null: false
      t.integer :credits, default: 100, null: false
      t.string :referral_code
      t.string :referred_by
      t.boolean :email_verified, default: false, null: false
      t.datetime :last_seen_at
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :referral_code, unique: true
    add_index :users, :role
    add_index :users, :tier
    add_index :users, :reset_password_token, unique: true
    add_index :users, :confirmation_token, unique: true
  end
end
