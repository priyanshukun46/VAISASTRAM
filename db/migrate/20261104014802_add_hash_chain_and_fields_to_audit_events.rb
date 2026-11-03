class AddHashChainAndFieldsToAuditEvents < ActiveRecord::Migration[8.0]
  def up
    add_reference :audit_events, :task, foreign_key: { to_table: :tasks, on_delete: :nullify }, index: true

    add_column :audit_events, :tool_name, :string
    add_column :audit_events, :action_fingerprint, :string
    add_column :audit_events, :policy_decision, :string
    add_column :audit_events, :status, :string

    add_column :audit_events, :chain_id, :string
    add_column :audit_events, :sequence_number, :integer
    add_column :audit_events, :prev_event_hash, :string
    add_column :audit_events, :event_hash, :string
    add_column :audit_events, :hash_version, :string, default: "v1"

    add_index :audit_events, :tool_name
    add_index :audit_events, :action_fingerprint
    add_index :audit_events, :policy_decision
    add_index :audit_events, :status
    add_index :audit_events, :chain_id
    add_index :audit_events, :event_hash
    add_index :audit_events, [:chain_id, :sequence_number]
    add_index :audit_events, [:task_id, :occurred_at]

    # Backfill task_id from executions
    execute <<-SQL
      UPDATE audit_events
      SET task_id = executions.task_id
      FROM executions
      WHERE audit_events.execution_id = executions.id
        AND audit_events.task_id IS NULL;
    SQL

    # Backfill chain_id for legacy records
    execute <<-SQL
      UPDATE audit_events
      SET chain_id = CASE
        WHEN execution_id IS NOT NULL THEN 'execution:' || execution_id
        WHEN task_id IS NOT NULL THEN 'task:' || task_id
        ELSE 'system:global'
      END
      WHERE chain_id IS NULL;
    SQL
  end

  def down
    remove_index :audit_events, [:task_id, :occurred_at] if index_exists?(:audit_events, [:task_id, :occurred_at])
    remove_index :audit_events, [:chain_id, :sequence_number] if index_exists?(:audit_events, [:chain_id, :sequence_number])
    remove_index :audit_events, :event_hash if index_exists?(:audit_events, :event_hash)
    remove_index :audit_events, :chain_id if index_exists?(:audit_events, :chain_id)
    remove_index :audit_events, :status if index_exists?(:audit_events, :status)
    remove_index :audit_events, :policy_decision if index_exists?(:audit_events, :policy_decision)
    remove_index :audit_events, :action_fingerprint if index_exists?(:audit_events, :action_fingerprint)
    remove_index :audit_events, :tool_name if index_exists?(:audit_events, :tool_name)

    remove_column :audit_events, :hash_version if column_exists?(:audit_events, :hash_version)
    remove_column :audit_events, :event_hash if column_exists?(:audit_events, :event_hash)
    remove_column :audit_events, :prev_event_hash if column_exists?(:audit_events, :prev_event_hash)
    remove_column :audit_events, :sequence_number if column_exists?(:audit_events, :sequence_number)
    remove_column :audit_events, :chain_id if column_exists?(:audit_events, :chain_id)

    remove_column :audit_events, :status if column_exists?(:audit_events, :status)
    remove_column :audit_events, :policy_decision if column_exists?(:audit_events, :policy_decision)
    remove_column :audit_events, :action_fingerprint if column_exists?(:audit_events, :action_fingerprint)
    remove_column :audit_events, :tool_name if column_exists?(:audit_events, :tool_name)

    remove_reference :audit_events, :task if column_exists?(:audit_events, :task_id)
  end
end
