class DashboardController < ApplicationController
  def index
    primary_label = if Ai::Configuration.mode == "cloud"
      "Gemini (#{Ai::ModelCatalog.gemini_model})"
    elsif Ai::Configuration.mode == "local"
      "Ollama (#{Ai::Configuration.ollama_model})"
    else
      "Ollama (#{Ai::Configuration.ollama_model}) [Hybrid]"
    end

    fallback_label = if Ai::Configuration.cloud_fallback_enabled?
      "Groq (#{Ai::ModelCatalog.groq_model}) [Standby]"
    else
      "Disabled"
    end

    @metrics = {
      total_agents: Agent.count,
      active_tasks: Task.active.count,
      pending_approvals: Approval.pending.count,
      blocked_actions: AgentStep.blocked.count + Task.blocked.count,
      system_status: "Operational",
      policy_engine_status: "Active (Default-Deny)",
      ai_primary_status: primary_label,
      ai_fallback_status: fallback_label
    }

    @recent_executions = Execution.recent.limit(5).includes(:task, :agent)
    @pending_approvals = Approval.pending.includes(agent_step: :execution).limit(5)
  end
end
