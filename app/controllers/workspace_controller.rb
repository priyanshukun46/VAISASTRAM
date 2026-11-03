class WorkspaceController < ApplicationController
  def index
    @agents = Agent.where(user: current_user).or(Agent.where(user: nil)).order(:id)
    @selected_agent = @agents.find_by(id: params[:agent_id]) || @agents.first || Agent.first
    @recent_tasks = current_user.tasks.order(created_at: :desc).limit(10).includes(executions: :agent_steps)
    @active_task = @recent_tasks.find_by(id: params[:task_id]) || @recent_tasks.first
    @active_execution = @active_task&.executions&.order(created_at: :desc)&.first
  end

  def create
    instruction = params[:instruction].to_s.strip
    if instruction.blank?
      redirect_to workspace_path, alert: "Please provide a task instruction or question."
      return
    end

    agent = Agent.find_by(id: params[:agent_id]) || current_user.agents.first || Agent.first
    unless agent
      agent = Agent.create!(
        user: current_user,
        name: "Financial Operations Agent",
        description: "Autonomous financial and accounting workflow agent with strict policy governance.",
        configuration: { "allowed_tools" => ["lookup_invoice", "verify_invoice", "prepare_payment"] }
      )
    end

    task = current_user.tasks.create!(
      agent: agent,
      title: instruction.truncate(60),
      instruction: instruction,
      submitted_at: Time.current
    )

    result = Planning::AgentPlanner.plan(task: task, user: current_user)

    if result.success?
      notice_msg = if result.clarification_needed?
        "Agent analyzed your instruction and requested clarification."
      elsif result.requires_action?
        "Agent proposed a #{result.steps.size}-step execution plan. Actions remain pending policy evaluation."
      else
        "Agent responded to your instruction."
      end
      redirect_to workspace_path(task_id: task.id), notice: notice_msg
    else
      redirect_to workspace_path(task_id: task.id), alert: "Planning failed: #{result.error_message}"
    end
  end
end
