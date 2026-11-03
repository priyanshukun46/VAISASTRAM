class PoliciesController < ApplicationController
  CRITICAL_ACTION_KEYS = %w[delete_financial_record delete_records].freeze

  def index
    @system_policies = Policy.system_wide.by_priority
    @user_policies = Policy.user_defined.where(user: current_user).by_priority
    @code_rules = Policies::Evaluator.new.rules
    @recent_decisions = AuditEvent.where(actor_type: "policy_engine", event_type: "policy_evaluated")
                                  .recent
                                  .limit(10)
    @last_evaluation = @recent_decisions.first
  end

  def toggle
    unless current_user.admin?
      redirect_to policies_path, alert: "Authorization Denied: Only administrators can modify security policies."
      return
    end

    policy = Policy.find(params[:id])

    # Guard against disabling critical security policies
    if CRITICAL_ACTION_KEYS.include?(policy.action_key) && policy.enabled?
      redirect_to policies_path, alert: "Security Protection: Critical security policy '#{policy.name}' cannot be disabled."
      return
    end

    new_status = !policy.enabled?
    policy.update!(enabled: new_status)

    # Immutable audit logging for administrative policy modification
    AuditEvent.create!(
      user: current_user,
      event_type: "policy_modified",
      actor_type: "user",
      actor_id: current_user.email,
      occurred_at: Time.current,
      metadata: {
        policy_id: policy.id,
        policy_name: policy.name,
        action_key: policy.action_key,
        enabled: new_status,
        modified_by: current_user.email,
        modified_by_role: current_user.role
      }
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "policy_#{policy.id}",
          partial: "policies/policy_row",
          locals: { policy: policy }
        )
      end
      format.html { redirect_to policies_path, notice: "Policy '#{policy.name}' #{new_status ? 'enabled' : 'disabled'} successfully." }
    end
  end
end
