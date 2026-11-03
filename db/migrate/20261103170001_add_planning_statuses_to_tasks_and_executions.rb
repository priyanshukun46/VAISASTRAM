class AddPlanningStatusesToTasksAndExecutions < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :tasks, name: "check_tasks_status"
    add_check_constraint :tasks, "status IN ('pending', 'planning', 'planned', 'running', 'completed', 'failed', 'cancelled', 'blocked')", name: "check_tasks_status"

    remove_check_constraint :executions, name: "check_executions_status"
    add_check_constraint :executions, "status IN ('pending', 'planning', 'planned', 'running', 'completed', 'failed', 'paused', 'blocked')", name: "check_executions_status"
  end
end
