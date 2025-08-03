# frozen_string_literal: true

class CreateUsageQuotas < ActiveRecord::Migration[7.0]
  def change
    create_table :usage_quotas do |t|
      t.references :user, null: false, foreign_key: true
      t.string :tier, null: false
      t.integer :projects_limit
      t.integer :projects_used, default: 0
      t.integer :team_members_limit
      t.integer :team_members_used, default: 0
      t.bigint :storage_limit_bytes
      t.bigint :storage_used_bytes, default: 0
      t.integer :api_calls_limit
      t.integer :api_calls_used, default: 0
      t.date :current_period_start
      t.date :current_period_end
      t.json :features_enabled, default: {}

      t.timestamps
    end

    add_index :usage_quotas, [:user_id, :tier], unique: true
    add_index :usage_quotas, :current_period_start
    add_index :usage_quotas, :current_period_end
  end
end