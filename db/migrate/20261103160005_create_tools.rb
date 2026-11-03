class CreateTools < ActiveRecord::Migration[8.1]
  def change
    create_table :tools do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.jsonb :input_schema, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.string :risk_level, null: false, default: "low"
      t.string :required_permission

      t.timestamps
    end

    add_index :tools, :key, unique: true
    add_index :tools, :enabled
    add_check_constraint :tools, "risk_level IN ('low', 'medium', 'high', 'critical')", name: "check_tools_risk_level"
  end
end
