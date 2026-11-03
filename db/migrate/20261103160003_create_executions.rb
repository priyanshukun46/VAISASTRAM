class CreateExecutions < ActiveRecord::Migration[8.1]
  def change
    create_table :executions do |t|
      t.references :task, null: false, foreign_key: { on_delete: :cascade }
      t.references :agent, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "pending"
      t.string :provider, null: false, default: "gemini"
      t.string :ai_model, null: false, default: "gemini-2.5-pro"
      t.jsonb :plan, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end

    add_index :executions, :status
    add_index :executions, :provider
    add_index :executions, :ai_model
    add_check_constraint :executions, "status IN ('pending', 'running', 'completed', 'failed', 'paused', 'blocked')", name: "check_executions_status"
  end
end
