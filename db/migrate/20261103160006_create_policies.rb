class CreatePolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :policies do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.text :description
      t.string :action_key, null: false
      t.string :effect, null: false, default: "deny"
      t.jsonb :conditions, null: false, default: {}
      t.integer :priority, null: false, default: 100
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :policies, :action_key
    add_index :policies, :priority
    add_index :policies, :enabled
    add_index :policies, [:action_key, :priority], name: "index_policies_on_action_key_and_priority"
    add_check_constraint :policies, "effect IN ('allow', 'deny', 'require_approval')", name: "check_policies_effect"
  end
end
