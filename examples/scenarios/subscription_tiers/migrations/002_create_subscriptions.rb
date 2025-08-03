# frozen_string_literal: true

class CreateSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :polar_subscription_id, null: false
      t.string :polar_product_id, null: false
      t.string :tier, null: false
      t.string :status, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.string :currency, default: 'USD'
      t.string :billing_interval, null: false # monthly, yearly
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :trial_start
      t.datetime :trial_end
      t.datetime :cancelled_at
      t.boolean :cancel_at_period_end, default: false
      t.json :metadata

      t.timestamps
    end

    add_index :subscriptions, :polar_subscription_id, unique: true
    add_index :subscriptions, :polar_product_id
    add_index :subscriptions, :status
    add_index :subscriptions, :tier
    add_index :subscriptions, [:user_id, :status]
  end
end