# frozen_string_literal: true

class AddGithubFieldsToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :github_username, :string
    add_column :users, :github_user_id, :string
    add_column :users, :github_access_token, :text # Encrypted
    add_column :users, :github_email, :string
    add_column :users, :github_name, :string
    add_column :users, :github_avatar_url, :string
    add_column :users, :github_profile_url, :string
    add_column :users, :github_connected_at, :datetime
    add_column :users, :github_permissions, :json, default: {}
    
    add_index :users, :github_username, unique: true
    add_index :users, :github_user_id, unique: true
    add_index :users, :github_email
  end
end