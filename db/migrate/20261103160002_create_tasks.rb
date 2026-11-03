class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :agent, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false
      t.text :instruction, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :submitted_at, null: false

      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :submitted_at
    add_check_constraint :tasks, "status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'blocked')", name: "check_tasks_status"
  end
end
