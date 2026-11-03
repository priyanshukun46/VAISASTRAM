class AuditController < ApplicationController
  before_action :authenticate_user!

  def index
    base_scope = if current_user.admin? || current_user.auditor?
      AuditEvent.all
    else
      AuditEvent.where(user: current_user).or(
        AuditEvent.where(task_id: current_user.tasks.select(:id))
      )
    end

    @total_count = base_scope.count

    # Filtering
    @selected_event = params[:event_type].presence
    @selected_actor = params[:actor_type].presence
    @selected_tool = params[:tool_name].presence
    @selected_chain = params[:chain_id].presence

    base_scope = base_scope.where(event_type: @selected_event) if @selected_event
    base_scope = base_scope.where(actor_type: @selected_actor) if @selected_actor
    base_scope = base_scope.where(tool_name: @selected_tool) if @selected_tool
    base_scope = base_scope.where(chain_id: @selected_chain) if @selected_chain

    @filtered_count = base_scope.count

    # Pagination
    @page = [params[:page].to_i, 1].max
    @per_page = 25
    @total_pages = [(@filtered_count.to_f / @per_page).ceil, 1].max
    offset = (@page - 1) * @per_page

    @audit_events = base_scope.order(occurred_at: :desc, id: :desc).offset(offset).limit(@per_page)

    # Distinct options for filters
    @event_types = Audit::EventSchema::ALL_EVENT_TYPES
    @actor_types = Audit::EventSchema::ACTOR_TYPES
  end

  def verify
    chain_id = params[:chain_id].presence

    @verification_result = if chain_id.present?
      Audit::IntegrityVerifier.verify_chain(chain_id)
    else
      # Verify execution of latest active task if none specified
      last_event = AuditEvent.order(occurred_at: :desc).first
      chain_to_verify = last_event&.chain_id || "system:global"
      Audit::IntegrityVerifier.verify_chain(chain_to_verify)
    end

    respond_to do |format|
      format.html { redirect_to audit_path, notice: "Verification completed: #{@verification_result.valid? ? 'All hash links valid' : 'Integrity errors detected!'}" }
      format.turbo_stream
    end
  end
end
