class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :execution, foreign_key: { on_delete: :nullify }
      t.references :agent_step, foreign_key: { on_delete: :nullify }
      t.references :approval, foreign_key: { on_delete: :nullify }
      t.string :event_type, null: false
      t.string :actor_type, null: false, default: "system"
      t.string :actor_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :audit_events, :event_type
    add_index :audit_events, :occurred_at
    add_index :audit_events, [:execution_id, :occurred_at], name: "index_audit_events_on_execution_and_occurred_at"
    add_check_constraint :audit_events, "actor_type IN ('user', 'agent', 'policy_engine', 'system')", name: "check_audit_events_actor_type"
  end
end
