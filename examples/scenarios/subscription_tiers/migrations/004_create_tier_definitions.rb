# frozen_string_literal: true

class CreateTierDefinitions < ActiveRecord::Migration[7.0]
  def change
    create_table :tier_definitions do |t|
      t.string :name, null: false
      t.string :display_name, null: false
      t.text :description
      t.decimal :monthly_price, precision: 10, scale: 2
      t.decimal :yearly_price, precision: 10, scale: 2
      t.string :polar_monthly_product_id
      t.string :polar_yearly_product_id
      t.integer :projects_limit
      t.integer :team_members_limit
      t.bigint :storage_limit_bytes
      t.integer :api_calls_limit
      t.json :features, default: {}
      t.boolean :active, default: true
      t.integer :sort_order, default: 0

      t.timestamps
    end

    add_index :tier_definitions, :name, unique: true
    add_index :tier_definitions, :active
    add_index :tier_definitions, :sort_order
  end
end