class AddFieldsAndConstraintToApprovals < ActiveRecord::Migration[8.0]
  def up
    # 1. Allow agent_step_id to be nullable if applicable
    change_column_null :approvals, :agent_step_id, true

    # 2. Add relational context references
    add_reference :approvals, :user, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
    add_reference :approvals, :task, foreign_key: { to_table: :tasks, on_delete: :cascade }, index: true
    add_reference :approvals, :execution, foreign_key: { to_table: :executions, on_delete: :cascade }, index: true

    # 3. Add action, fingerprint, and governance metadata
    add_column :approvals, :tool_name, :string
    add_column :approvals, :action_arguments, :jsonb, default: {}, null: false
    add_column :approvals, :action_fingerprint, :string
    add_column :approvals, :policy_decision_reference, :string
    add_column :approvals, :requested_at, :datetime

    # 4. Add performance indexes
    add_index :approvals, :tool_name
    add_index :approvals, :action_fingerprint
    add_index :approvals, [:status, :expires_at]

    # 5. Update status check constraint to support full Phase 7 lifecycle
    remove_check_constraint :approvals, name: "check_approvals_status"
    add_check_constraint :approvals,
      "status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'expired'::character varying, 'invalidated'::character varying, 'executed'::character varying, 'failed'::character varying]::text[])",
      name: "check_approvals_status"

    # 6. Backfill existing records
    execute <<-SQL
      UPDATE approvals
      SET action_fingerprint = action_digest,
          requested_at = COALESCE(requested_at, created_at)
      WHERE action_fingerprint IS NULL;
    SQL

    execute <<-SQL
      UPDATE approvals
      SET execution_id = agent_steps.execution_id,
          tool_name = agent_steps.action_key,
          action_arguments = COALESCE(agent_steps.arguments, '{}'::jsonb)
      FROM agent_steps
      WHERE approvals.agent_step_id = agent_steps.id
        AND approvals.execution_id IS NULL;
    SQL

    execute <<-SQL
      UPDATE approvals
      SET task_id = executions.task_id
      FROM executions
      WHERE approvals.execution_id = executions.id
        AND approvals.task_id IS NULL;
    SQL

    execute <<-SQL
      UPDATE approvals
      SET user_id = tasks.user_id
      FROM tasks
      WHERE approvals.task_id = tasks.id
        AND approvals.user_id IS NULL;
    SQL
  end

  def down
    remove_check_constraint :approvals, name: "check_approvals_status" rescue nil
    add_check_constraint :approvals,
      "status::text = ANY (ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'expired'::character varying]::text[])",
      name: "check_approvals_status" rescue nil

    remove_index :approvals, [:status, :expires_at] if index_exists?(:approvals, [:status, :expires_at])
    remove_index :approvals, :action_fingerprint if index_exists?(:approvals, :action_fingerprint)
    remove_index :approvals, :tool_name if index_exists?(:approvals, :tool_name)

    remove_column :approvals, :requested_at if column_exists?(:approvals, :requested_at)
    remove_column :approvals, :policy_decision_reference if column_exists?(:approvals, :policy_decision_reference)
    remove_column :approvals, :action_fingerprint if column_exists?(:approvals, :action_fingerprint)
    remove_column :approvals, :action_arguments if column_exists?(:approvals, :action_arguments)
    remove_column :approvals, :tool_name if column_exists?(:approvals, :tool_name)

    remove_reference :approvals, :execution if column_exists?(:approvals, :execution_id)
    remove_reference :approvals, :task if column_exists?(:approvals, :task_id)
    remove_reference :approvals, :user if column_exists?(:approvals, :user_id)

    change_column_null :approvals, :agent_step_id, false
  end
end
