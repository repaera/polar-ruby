# frozen_string_literal: true

class CreateUsageRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :usage_records do |t|
      t.references :user, null: false, foreign_key: true
      t.references :credit_transaction, null: false, foreign_key: true
      t.string :operation_type, null: false
      t.string :operation_id
      t.decimal :credits_consumed, precision: 15, scale: 2, null: false
      t.decimal :cost_per_unit, precision: 10, scale: 6
      t.integer :units_consumed, default: 1
      t.json :operation_details, default: {}
      t.string :api_endpoint
      t.string :request_id
      t.string :user_agent
      t.string :ip_address
      t.integer :response_time_ms
      t.string :status # success, error, partial
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :usage_records, :operation_type
    add_index :usage_records, :operation_id
    add_index :usage_records, :api_endpoint
    add_index :usage_records, :status
    add_index :usage_records, [:user_id, :operation_type]
    add_index :usage_records, [:user_id, :created_at]
    add_index :usage_records, :started_at
  end
end