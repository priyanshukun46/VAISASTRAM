class DashboardController < ApplicationController
  def index
    @metrics = {
      total_agents: Agent.count,
      active_tasks: Task.active.count,
      pending_approvals: Approval.pending.count,
      blocked_actions: AgentStep.blocked.count + Task.blocked.count,
      system_status: "Operational",
      policy_engine_status: "Active (Default-Deny)",
      ai_primary_status: "Gemini 2.5 Pro (Configured)",
      ai_fallback_status: "Groq Llama-3.3-70b (Standby)"
    }

    @recent_executions = Execution.recent.limit(5).includes(:task, :agent)
    @pending_approvals = Approval.pending.includes(agent_step: :execution).limit(5)
  end
end
