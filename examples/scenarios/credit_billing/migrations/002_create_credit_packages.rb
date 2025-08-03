# frozen_string_literal: true

class CreateCreditPackages < ActiveRecord::Migration[7.0]
  def change
    create_table :credit_packages do |t|
      t.string :name, null: false
      t.text :description
      t.decimal :credits, precision: 15, scale: 2, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :currency, default: 'USD', null: false
      t.decimal :price_per_credit, precision: 10, scale: 6, null: false
      t.integer :discount_percentage, default: 0
      t.string :polar_product_id
      t.boolean :active, default: true
      t.boolean :featured, default: false
      t.integer :sort_order, default: 0
      t.json :metadata, default: {}
      t.datetime :expires_at
      t.integer :max_purchases_per_user
      t.text :terms

      t.timestamps
    end

    add_index :credit_packages, :active
    add_index :credit_packages, :featured
    add_index :credit_packages, :sort_order
    add_index :credit_packages, :polar_product_id, unique: true
    add_index :credit_packages, :price_per_credit
  end
end