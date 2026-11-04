class WorkspaceController < ApplicationController
  def index
    @agents = accessible_agents.order(:id)
    @selected_agent = @agents.find_by(id: params[:agent_id]) || @agents.find_by(name: "VAISASTRAM Agent") || @agents.first
    unless @selected_agent
      @selected_agent = Agent.create!(
        user: current_user,
        name: "VAISASTRAM Agent",
        description: "General-purpose governed autonomous AI agent platform with independent Ruby policy enforcement, conversational reasoning, and allowlisted domain tools.",
        configuration: { "allowed_tools" => ["lookup_invoice", "verify_invoice", "prepare_payment"] }
      )
    end
    remembered = Ai::ModelCatalog.find(session[:ai_model]) if session[:ai_model].present?
    @selected_model = remembered&.available? ? remembered.id : Ai::ModelCatalog::AUTO
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

    choice = Ai::ModelCatalog.find(params[:ai_model])
    if choice.nil?
      redirect_to workspace_path, alert: "Unknown AI model selected."
      return
    end
    unless choice.available?
      redirect_to workspace_path, alert: "#{choice.label} is not configured (#{choice.reason})."
      return
    end
    session[:ai_model] = choice.id

    # SECURITY: only agents the user may access; a foreign agent_id falls back to the user's own.
    agent = accessible_agents.find_by(id: params[:agent_id]) ||
            current_user.agents.find_by(name: "VAISASTRAM Agent") ||
            current_user.agents.first
    unless agent
      agent = Agent.create!(
        user: current_user,
        name: "VAISASTRAM Agent",
        description: "General-purpose governed autonomous AI agent platform with independent Ruby policy enforcement, conversational reasoning, and allowlisted domain tools.",
        configuration: { "allowed_tools" => ["lookup_invoice", "verify_invoice", "prepare_payment"] }
      )
    end

    task = current_user.tasks.create!(
      agent: agent,
      title: instruction.truncate(60),
      instruction: instruction,
      submitted_at: Time.current
    )

    # Record task creation in audit trail
    Audit::Recorder.record!(
      event_type: "task_created",
      actor_type: "user",
      actor_id: current_user.id.to_s,
      user: current_user,
      task: task,
      metadata: {
        title: task.title,
        agent_name: agent.name,
        instruction_preview: instruction.truncate(120)
      }
    )

    parent_task = current_user.tasks.find_by(id: params[:parent_task_id]) if params[:parent_task_id].present?
    result = Planning::AgentPlanner.plan(
      task: task,
      user: current_user,
      provider_router: Ai::ModelCatalog.router_for(choice.id),
      context_task: parent_task
    )

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

  private

  def accessible_agents
    current_user.admin? ? Agent.all : current_user.agents
  end
end
