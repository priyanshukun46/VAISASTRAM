class AddPerformanceIndexesForGovernance < ActiveRecord::Migration[8.1]
  def change
    add_index :executions, :created_at unless index_exists?(:executions, :created_at)
    add_index :tasks, :created_at unless index_exists?(:tasks, :created_at)
    add_index :approvals, :created_at unless index_exists?(:approvals, :created_at)
    add_index :agent_steps, :created_at unless index_exists?(:agent_steps, :created_at)
    add_index :agent_steps, :policy_decision unless index_exists?(:agent_steps, :policy_decision)
  end
end
