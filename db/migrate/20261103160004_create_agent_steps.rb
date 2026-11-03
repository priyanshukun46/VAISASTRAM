class CreateAgentSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_steps do |t|
      t.references :execution, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.string :action_key, null: false
      t.jsonb :arguments, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.string :risk_level, null: false, default: "unknown"
      t.string :policy_decision
      t.jsonb :result, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :agent_steps, [:execution_id, :position], unique: true, name: "index_agent_steps_on_execution_and_position"
    add_index :agent_steps, :action_key
    add_index :agent_steps, :status
    add_index :agent_steps, :risk_level
    add_check_constraint :agent_steps, "status IN ('pending', 'evaluating_policy', 'waiting_approval', 'approved', 'rejected', 'running', 'completed', 'failed', 'blocked')", name: "check_agent_steps_status"
    add_check_constraint :agent_steps, "risk_level IN ('unknown', 'low', 'medium', 'high', 'critical')", name: "check_agent_steps_risk_level"
    add_check_constraint :agent_steps, "policy_decision IS NULL OR policy_decision IN ('allow', 'deny', 'require_approval')", name: "check_agent_steps_policy_decision"
  end
end
