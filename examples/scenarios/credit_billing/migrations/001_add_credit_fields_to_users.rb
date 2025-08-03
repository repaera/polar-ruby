# frozen_string_literal: true

class AddCreditFieldsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :credit_balance, :decimal, precision: 15, scale: 2, default: 0, null: false
    add_column :users, :auto_recharge_enabled, :boolean, default: false
    add_column :users, :auto_recharge_threshold, :decimal, precision: 15, scale: 2, default: 100
    add_column :users, :auto_recharge_amount, :decimal, precision: 15, scale: 2, default: 1000
    add_column :users, :auto_recharge_package_id, :bigint
    add_column :users, :total_credits_purchased, :decimal, precision: 15, scale: 2, default: 0
    add_column :users, :total_credits_consumed, :decimal, precision: 15, scale: 2, default: 0
    add_column :users, :last_recharge_at, :datetime
    add_column :users, :credit_alerts_enabled, :boolean, default: true
    
    add_index :users, :credit_balance
    add_index :users, :auto_recharge_enabled
    add_index :users, :auto_recharge_package_id
  end
end