# frozen_string_literal: true

class AddDeviseToUsers < ActiveRecord::Migration[8.1]
  def change
    if table_exists?(:users)
      change_table :users do |t|
        t.string :name, null: false, default: "Operator" unless column_exists?(:users, :name)
        t.string :role, null: false, default: "operator" unless column_exists?(:users, :role)

        ## Devise fields
        t.string :email, null: false, default: "" unless column_exists?(:users, :email)
        t.string :encrypted_password, null: false, default: "" unless column_exists?(:users, :encrypted_password)
        t.string :reset_password_token unless column_exists?(:users, :reset_password_token)
        t.datetime :reset_password_sent_at unless column_exists?(:users, :reset_password_sent_at)
        t.datetime :remember_created_at unless column_exists?(:users, :remember_created_at)
        t.integer :sign_in_count, default: 0, null: false unless column_exists?(:users, :sign_in_count)
        t.datetime :current_sign_in_at unless column_exists?(:users, :current_sign_in_at)
        t.datetime :last_sign_in_at unless column_exists?(:users, :last_sign_in_at)
        t.string :current_sign_in_ip unless column_exists?(:users, :current_sign_in_ip)
        t.string :last_sign_in_ip unless column_exists?(:users, :last_sign_in_ip)
      end

      # Remove obsolete legacy columns if migrating from earlier auth generator
      remove_column :users, :email_address, :string if column_exists?(:users, :email_address)
      remove_column :users, :password_digest, :string if column_exists?(:users, :password_digest)
    else
      create_table :users do |t|
        ## Governance Identity
        t.string :name, null: false, default: "Operator"
        t.string :role, null: false, default: "operator"

        ## Database authenticatable
        t.string :email,              null: false, default: ""
        t.string :encrypted_password, null: false, default: ""

        ## Recoverable
        t.string   :reset_password_token
        t.datetime :reset_password_sent_at

        ## Rememberable
        t.datetime :remember_created_at

        ## Trackable
        t.integer  :sign_in_count, default: 0, null: false
        t.datetime :current_sign_in_at
        t.datetime :last_sign_in_at
        t.string   :current_sign_in_ip
        t.string   :last_sign_in_ip

        t.timestamps null: false
      end
    end

    add_index :users, :email, unique: true unless index_exists?(:users, :email)
    add_index :users, :reset_password_token, unique: true unless index_exists?(:users, :reset_password_token)
    add_index :users, :role unless index_exists?(:users, :role)
  end
end
