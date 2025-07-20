class AddTierToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :tier, :integer
  end
end
