class CreateMcpServersAndTools < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_servers do |t|
      t.references :user, foreign_key: { on_delete: :cascade }, null: true
      t.string :name, null: false
      t.string :server_identifier, null: false
      t.text :description
      t.string :transport_type, null: false, default: "stdio"
      t.string :command
      t.jsonb :arguments, default: [], null: false
      t.string :endpoint_url
      t.text :environment_variables
      t.text :authentication_configuration
      t.integer :connection_timeout, default: 15, null: false
      t.integer :request_timeout, default: 30, null: false
      t.boolean :enabled, default: false, null: false
      t.string :status, default: "disconnected", null: false
      t.text :error_message
      t.string :protocol_version, default: "2024-11-05"
      t.jsonb :server_info, default: {}, null: false
      t.jsonb :capabilities, default: {}, null: false
      t.integer :configuration_version, default: 1, null: false
      t.boolean :allow_local_connections, default: false, null: false
      t.datetime :last_connected_at
      t.datetime :last_health_check_at

      t.timestamps
    end

    add_index :mcp_servers, :server_identifier, unique: true
    add_index :mcp_servers, :status
    add_index :mcp_servers, :enabled
    add_index :mcp_servers, :transport_type

    create_table :mcp_tools do |t|
      t.references :mcp_server, foreign_key: { on_delete: :cascade }, null: false
      t.string :external_tool_name, null: false
      t.string :namespaced_tool_key, null: false
      t.text :description
      t.jsonb :input_schema, default: {}, null: false
      t.string :schema_hash, null: false
      t.boolean :enabled, default: false, null: false
      t.string :risk_classification, default: "medium", null: false
      t.string :policy_decision, default: "deny", null: false
      t.datetime :last_discovered_at
      t.datetime :last_invoked_at
      t.integer :invocation_count, default: 0, null: false

      t.timestamps
    end

    add_index :mcp_tools, :namespaced_tool_key, unique: true
    add_index :mcp_tools, [:mcp_server_id, :external_tool_name], unique: true
    add_index :mcp_tools, :enabled
    add_index :mcp_tools, :policy_decision
  end
end
