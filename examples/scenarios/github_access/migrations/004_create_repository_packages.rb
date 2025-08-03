# frozen_string_literal: true

class CreateRepositoryPackages < ActiveRecord::Migration[7.0]
  def change
    create_table :repository_packages do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, null: false
      t.string :currency, default: 'USD'
      t.string :billing_type # one_time, subscription, custom
      t.string :billing_interval # monthly, yearly (for subscriptions)
      t.string :polar_product_id
      t.boolean :active, default: true
      t.boolean :featured, default: false
      t.integer :sort_order, default: 0
      t.text :features # JSON or text list of features
      t.text :marketing_copy
      t.string :access_duration # permanent, 1_year, custom
      t.integer :max_users # Nil = unlimited users per purchase
      t.json :metadata, default: {}
      t.string :category
      t.string :difficulty_level # beginner, intermediate, advanced
      t.text :requirements # Prerequisites or requirements
      t.text :changelog # Package update history

      t.timestamps
    end

    add_index :repository_packages, :slug, unique: true
    add_index :repository_packages, :polar_product_id, unique: true
    add_index :repository_packages, :active
    add_index :repository_packages, :featured
    add_index :repository_packages, :category
    add_index :repository_packages, :billing_type
  end
end