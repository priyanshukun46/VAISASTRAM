class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.jsonb :configuration, null: false, default: {}

      t.timestamps
    end

    add_index :agents, :status
    add_index :agents, :name
    add_check_constraint :agents, "status IN ('active', 'paused', 'archived')", name: "check_agents_status"
  end
end
