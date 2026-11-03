module Replay
  class ExecutionReplayer
    def self.replay(execution:, user:, mode: :inspection)
      new(execution: execution, user: user, mode: mode).replay
    end

    attr_reader :execution, :user, :mode, :context

    def initialize(execution:, user:, mode: :inspection)
      @execution = execution
      @user = user
      @mode = mode.to_sym
      @context = Replay::ReplayContext.new(execution: execution, user: user, mode: @mode)
    end

    def replay
      # 1. Enforce access control and security validation
      Replay::ReplayValidator.validate!(@context)

      # 2. Verify hash chain integrity of original execution history
      chain_verification = Audit::IntegrityVerifier.verify_execution(@execution.id)

      # 3. Mode A: Inspection Replay (Historical Reconstruction)
      reconstructed_steps = reconstruct_historical_steps

      simulated_steps = []
      differences = []

      # 4. Mode B: Simulation Replay (Re-evaluate against current live policies)
      if @context.simulation?
        simulated_steps, differences = run_simulation_replay(reconstructed_steps)
      end

      Replay::ReplayResult.new(
        mode: @mode,
        session_id: @context.session_id,
        execution_id: @execution.id,
        task_id: @execution.task_id,
        reconstructed_status: @execution.status,
        reconstructed_plan: @execution.plan,
        reconstructed_steps: reconstructed_steps,
        simulated_steps: simulated_steps,
        differences: differences,
        audit_events_count: @context.events.size,
        hash_chain_valid: chain_verification.valid?,
        verification_report: chain_verification
      )
    end

    private

    def reconstruct_historical_steps
      @context.steps.map do |step|
        step_events = @context.events.select { |e| e.agent_step_id == step.id }
        approval = step.approvals.order(created_at: :desc).first

        {
          id: step.id,
          position: step.position,
          action_key: step.action_key,
          arguments: Replay::ReplayValidator.redact_sensitive(step.arguments || {}),
          policy_decision: step.policy_decision,
          status: step.status,
          result: Replay::ReplayValidator.redact_sensitive(step.result || {}),
          started_at: step.started_at,
          completed_at: step.completed_at,
          approval: approval ? {
            id: approval.id,
            status: approval.status,
            reviewer_name: approval.reviewer&.name,
            reviewed_at: approval.reviewed_at,
            rejection_reason: approval.rejection_reason
          } : nil,
          events: step_events.map { |e| { id: e.id, type: e.event_type, occurred_at: e.occurred_at, actor: "#{e.actor_type}:#{e.actor_id}" } }
        }
      end
    end

    def run_simulation_replay(reconstructed_steps)
      simulated = []
      diffs = []

      @context.steps.each do |step|
        # Reconstruct policy evaluation context using current active rules
        pol_context = Policies::Context.new(
          user: @context.user,
          agent: @execution.agent,
          task: @execution.task,
          execution: @execution,
          agent_step: step,
          action_key: step.action_key,
          arguments: step.arguments
        )

        # Run independent deterministic evaluation under current policy rules
        current_decision = Policies::Engine.evaluate(pol_context)

        # Safe simulated outcome (purely mock / sandboxed)
        simulated_output = mock_simulated_dispatch(step.action_key, step.arguments)

        sim_step = {
          position: step.position,
          action_key: step.action_key,
          current_policy_decision: current_decision.decision,
          policy_reason: current_decision.reason,
          historical_decision: step.policy_decision,
          simulated_result: simulated_output,
          divergent: step.policy_decision.to_s.downcase != current_decision.decision.to_s.downcase
        }

        if sim_step[:divergent]
          diffs << {
            position: step.position,
            action_key: step.action_key,
            historical_decision: step.policy_decision,
            current_decision: current_decision.decision,
            reason: current_decision.reason
          }
        end

        simulated << sim_step
      end

      [simulated, diffs]
    end

    # Strictly simulated handler - zero side effects, no real payments, no external APIs
    def mock_simulated_dispatch(action_key, args)
      case action_key
      when "retrieve_invoice", "lookup_invoice"
        { "invoice_id" => args["invoice_id"] || "INV-100", "status" => "simulated_retrieved", "amount" => 5000 }
      when "verify_invoice"
        { "invoice_id" => args["invoice_id"] || "INV-100", "status" => "simulated_verified", "valid" => true }
      when "get_vendor"
        { "vendor_id" => args["vendor_id"] || "VND-100", "status" => "simulated_active" }
      when "prepare_payment"
        {
          "voucher_id" => "SIM-VCH-#{SecureRandom.hex(4).upcase}",
          "amount" => args["amount"] || 0,
          "currency" => "INR",
          "status" => "simulated_voucher_only",
          "note" => "Simulated during execution replay. No real payment initiated."
        }
      else
        { "action" => action_key, "status" => "simulated_execution" }
      end
    end
  end
end
