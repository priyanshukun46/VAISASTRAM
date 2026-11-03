class ExecutionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_execution
  before_action :authorize_execution!

  def show
    redirect_to timeline_execution_path(@execution)
  end

  def timeline
    @task = @execution.task
    @agent = @execution.agent
    @steps = @execution.agent_steps.order(position: :asc)

    # Base query for events
    events_scope = AuditEvent.for_execution(@execution.id).chronological

    if params[:event_type].present?
      events_scope = events_scope.where(event_type: params[:event_type])
    end

    if params[:actor_type].present?
      events_scope = events_scope.where(actor_type: params[:actor_type])
    end

    if params[:tool_name].present?
      events_scope = events_scope.where(tool_name: params[:tool_name])
    end

    @events = events_scope.page(params[:page]).per(50) rescue events_scope.limit(100)
    @integrity_report = Audit::IntegrityVerifier.verify_execution(@execution.id)
  end

  def audit
    @task = @execution.task
    events_scope = AuditEvent.for_execution(@execution.id).chronological
    @events = events_scope.limit(100)
    @integrity_report = Audit::IntegrityVerifier.verify_execution(@execution.id)
  end

  def replay
    @mode = params[:mode] == "simulation" ? :simulation : :inspection

    @replay_result = Replay::ExecutionReplayer.replay(
      execution: @execution,
      user: current_user,
      mode: @mode
    )

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  private

  def set_execution
    @execution = Execution.includes(:task, :agent, agent_steps: :approvals).find(params[:id])
  end

  def authorize_execution!
    unless current_user.can_access?(@execution)
      redirect_to workspace_path, alert: "You are not authorized to view Execution ##{@execution.id}."
    end
  end
end
