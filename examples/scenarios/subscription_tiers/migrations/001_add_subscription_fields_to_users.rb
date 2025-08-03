# frozen_string_literal: true

class AddSubscriptionFieldsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :trial_ends_at, :datetime
    add_column :users, :polar_customer_id, :string
    add_column :users, :current_tier, :string, default: 'trial'
    add_column :users, :trial_started_at, :datetime
    add_column :users, :onboarding_completed, :boolean, default: false
    
    add_index :users, :polar_customer_id, unique: true
    add_index :users, :trial_ends_at
    add_index :users, :current_tier
  end
end