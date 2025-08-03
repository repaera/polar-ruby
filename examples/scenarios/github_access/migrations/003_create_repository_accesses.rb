# frozen_string_literal: true

class CreateRepositoryAccesses < ActiveRecord::Migration[7.0]
  def change
    create_table :repository_accesses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :github_repository, null: false, foreign_key: true
      t.string :access_level, null: false, default: 'read' # read, write, admin
      t.string :status, null: false, default: 'pending' # pending, invited, active, expired, revoked
      t.datetime :granted_at
      t.datetime :expires_at
      t.datetime :last_accessed_at
      t.datetime :invitation_sent_at
      t.datetime :invitation_accepted_at
      t.string :github_invitation_id
      t.string :purchase_reference # Link to order/subscription
      t.string :polar_order_id
      t.string :access_source # purchase, subscription, trial, bonus
      t.json :permissions, default: {}
      t.text :notes
      t.integer :access_count, default: 0
      t.datetime :revoked_at
      t.string :revoked_reason

      t.timestamps
    end

    add_index :repository_accesses, [:user_id, :github_repository_id], unique: true
    add_index :repository_accesses, :status
    add_index :repository_accesses, :access_level
    add_index :repository_accesses, :expires_at
    add_index :repository_accesses, :polar_order_id
    add_index :repository_accesses, :purchase_reference
    add_index :repository_accesses, :github_invitation_id
  end
end