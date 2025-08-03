# frozen_string_literal: true

class CreateCreditAlerts < ActiveRecord::Migration[7.0]
  def change
    create_table :credit_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :alert_type, null: false # low_balance, zero_balance, high_usage, auto_recharge_failed
      t.decimal :trigger_balance, precision: 15, scale: 2
      t.decimal :current_balance, precision: 15, scale: 2
      t.string :status, default: 'active' # active, acknowledged, dismissed
      t.text :message
      t.json :metadata, default: {}
      t.datetime :triggered_at
      t.datetime :acknowledged_at
      t.datetime :dismissed_at
      t.boolean :email_sent, default: false
      t.datetime :email_sent_at

      t.timestamps
    end

    add_index :credit_alerts, :alert_type
    add_index :credit_alerts, :status
    add_index :credit_alerts, :triggered_at
    add_index :credit_alerts, [:user_id, :alert_type]
    add_index :credit_alerts, [:user_id, :status]
  end
end