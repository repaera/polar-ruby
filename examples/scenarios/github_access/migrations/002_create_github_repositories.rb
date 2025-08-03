# frozen_string_literal: true

class CreateGithubRepositories < ActiveRecord::Migration[7.0]
  def change
    create_table :github_repositories do |t|
      t.string :name, null: false
      t.string :full_name, null: false # owner/repo format
      t.string :owner, null: false
      t.text :description
      t.string :github_id, null: false
      t.string :clone_url
      t.string :ssh_url
      t.string :html_url
      t.boolean :private, default: true
      t.string :default_branch, default: 'main'
      t.string :language
      t.bigint :size_kb
      t.integer :stargazers_count, default: 0
      t.integer :forks_count, default: 0
      t.datetime :last_pushed_at
      
      # Business logic fields
      t.boolean :active, default: true
      t.string :access_type # individual, package, organization
      t.decimal :price, precision: 10, scale: 2
      t.string :currency, default: 'USD'
      t.string :license_type # mit, commercial, proprietary
      t.text :access_instructions
      t.json :metadata, default: {}
      t.integer :max_users # Nil = unlimited
      t.datetime :access_expires_at
      
      # Polar integration
      t.string :polar_product_id
      t.string :category # library, framework, template, course, tool
      t.text :marketing_description
      t.boolean :featured, default: false
      t.integer :sort_order, default: 0

      t.timestamps
    end

    add_index :github_repositories, :github_id, unique: true
    add_index :github_repositories, :full_name, unique: true
    add_index :github_repositories, :owner
    add_index :github_repositories, :active
    add_index :github_repositories, :access_type
    add_index :github_repositories, :polar_product_id
    add_index :github_repositories, :category
    add_index :github_repositories, :featured
  end
end