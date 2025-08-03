# frozen_string_literal: true

class CreatePackageRepositories < ActiveRecord::Migration[7.0]
  def change
    create_table :package_repositories do |t|
      t.references :repository_package, null: false, foreign_key: true
      t.references :github_repository, null: false, foreign_key: true
      t.boolean :required, default: true # Whether access to this repo is required for the package
      t.string :access_level, default: 'read' # read, write, admin
      t.integer :sort_order, default: 0
      t.text :description # Role of this repository in the package

      t.timestamps
    end

    add_index :package_repositories, [:repository_package_id, :github_repository_id], 
              unique: true, name: 'index_package_repos_on_package_and_repo'
    add_index :package_repositories, :required
  end
end