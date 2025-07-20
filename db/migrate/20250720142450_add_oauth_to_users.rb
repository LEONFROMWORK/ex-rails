class AddOauthToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :avatar_url, :string

    add_index :users, [ :provider, :uid ], unique: true

    # Make password_digest nullable for OAuth users
    change_column_null :users, :password_digest, true
  end
end
