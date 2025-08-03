# frozen_string_literal: true

class CreateCreditTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :transaction_type, null: false # purchase, consumption, refund, bonus, adjustment
      t.decimal :amount, precision: 15, scale: 2, null: false
      t.decimal :balance_before, precision: 15, scale: 2, null: false
      t.decimal :balance_after, precision: 15, scale: 2, null: false
      t.string :description
      t.string :operation_type # api_call, image_processing, data_export, etc.
      t.string :operation_id # Reference to specific operation
      t.references :credit_package, foreign_key: true, null: true
      t.string :polar_order_id
      t.string :polar_transaction_id
      t.string :reference_id # External reference
      t.json :metadata, default: {}
      t.string :status, default: 'completed' # pending, completed, failed, refunded
      t.datetime :processed_at
      t.text :notes

      t.timestamps
    end

    add_index :credit_transactions, :transaction_type
    add_index :credit_transactions, :operation_type
    add_index :credit_transactions, :operation_id
    add_index :credit_transactions, :polar_order_id
    add_index :credit_transactions, :status
    add_index :credit_transactions, :processed_at
    add_index :credit_transactions, [:user_id, :transaction_type]
    add_index :credit_transactions, [:user_id, :created_at]
  end
end