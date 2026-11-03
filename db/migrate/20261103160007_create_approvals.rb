class CreateApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :approvals do |t|
      t.references :agent_step, null: false, foreign_key: { on_delete: :cascade }
      t.references :reviewer, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :status, null: false, default: "pending"
      t.string :action_digest, null: false
      t.datetime :expires_at
      t.datetime :reviewed_at
      t.text :rejection_reason

      t.timestamps
    end

    add_index :approvals, :status
    add_index :approvals, :action_digest
    add_index :approvals, :expires_at
    add_check_constraint :approvals, "status IN ('pending', 'approved', 'rejected', 'expired')", name: "check_approvals_status"
  end
end
