class AddProviderMetadataToExecutions < ActiveRecord::Migration[8.1]
  def change
    add_column :executions, :inference_duration, :float
    add_column :executions, :fallback_used, :boolean, default: false, null: false
    add_column :executions, :fallback_reason, :text
    add_column :executions, :retry_count, :integer, default: 0, null: false
  end
end
