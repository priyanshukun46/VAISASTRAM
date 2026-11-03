module Tools
  class ExecutionError < StandardError; end
  class PolicyBlockedError < ExecutionError; end
  class ApprovalRequiredError < ExecutionError; end
  class ArgumentValidationError < ExecutionError; end
  class PolicyBypassError < SecurityError; end

  class ExecutionResult
    attr_reader :status, :result, :decision, :step, :approval, :error_message

    def initialize(status:, result: {}, decision: nil, step: nil, approval: nil, error_message: nil)
      @status = status.to_s
      @result = result || {}
      @decision = decision
      @step = step
      @approval = approval
      @error_message = error_message
    end

    def success?
      @status == "completed"
    end

    def paused?
      @status == "paused" || @status == "waiting_approval"
    end

    def blocked?
      @status == "blocked" || @status == "denied"
    end

    def failed?
      @status == "failed"
    end
  end

  class Executor
    def self.execute(step:, user: nil)
      new(step: step, user: user).execute
    end

    def self.execute_action(user:, task:, action_key:, arguments: {}, execution: nil, agent_step: nil)
      new(
        step: agent_step,
        user: user,
        task: task,
        action_key: action_key,
        arguments: arguments,
        execution: execution
      ).execute
    end

    def self.resume_approved(approval, reviewer:)
      new(
        step: approval.agent_step,
        user: approval.effective_user,
        task: approval.effective_task,
        execution: approval.effective_execution,
        action_key: approval.effective_tool_name,
        arguments: approval.effective_arguments
      ).resume_approved(approval, reviewer: reviewer)
    end

    attr_reader :step, :user, :task, :execution, :action_key, :arguments

    def initialize(step: nil, user: nil, task: nil, execution: nil, action_key: nil, arguments: {})
      @step = step
      @user = user || step&.execution&.task&.user
      @task = task || step&.execution&.task
      @execution = execution || step&.execution
      @action_key = (action_key || step&.action_key).to_s.strip.downcase
      @arguments = (arguments.presence || step&.arguments || {}).deep_dup
    end

    def execute
      # 1. Action Validation
      validate_action!

      # 2. Independent Policy Engine Evaluation (Strict Security Gate)
      context = Policies::Context.new(
        user: @user,
        agent: @execution&.agent,
        task: @task,
        execution: @execution,
        agent_step: @step,
        action_key: @action_key,
        arguments: @arguments
      )

      decision = Policies::Engine.evaluate(context)

      # 3. Policy Precedence & Decision Branching
      if decision.denied?
        handle_deny!(decision)
      elsif decision.requires_approval?
        handle_require_approval!(decision)
      elsif decision.allowed?
        handle_allow!(decision)
      else
        # Any unexpected state fails closed
        handle_deny!(decision)
      end
    rescue Tools::PolicyBlockedError, Tools::ApprovalRequiredError
      raise
    rescue StandardError => e
      # Requirement: "Any policy error blocks execution. Never trust fallback."
      handle_system_error!(e)
    end

    def resume_approved(approval, reviewer:)
      unless approval.is_a?(Approval) && approval.approved?
        raise ArgumentValidationError, "A valid approved Approval record is required to resume execution"
      end

      # 1. Action Fingerprint Verification
      Approvals::FingerprintValidator.validate!(approval)

      # 2. Record approval_consumed audit event
      record_audit_event!(
        event_type: "approval_consumed",
        actor_type: "user",
        actor_id: reviewer.id.to_s,
        approval: approval,
        metadata: {
          reviewer_id: reviewer.id,
          reviewer_name: reviewer.name,
          action_fingerprint: approval.action_fingerprint,
          tool_name: @action_key
        }
      )

      # 3. Step & Execution transitions
      if @step.present?
        @step.update!(
          status: "running",
          started_at: Time.current
        )
      end

      if @execution.present? && @execution.status != "running"
        @execution.update!(status: "running")
      end

      # 4. Safe tool dispatch (Simulated)
      tool_output = dispatch_tool!(@action_key, @arguments)

      # 5. Mark step and approval executed
      if @step.present?
        @step.update!(
          status: "completed",
          result: tool_output,
          completed_at: Time.current
        )
      end

      approval.update_columns(status: "executed")

      # Update execution to completed if all steps are completed
      if @execution.present?
        remaining = @execution.agent_steps.where.not(id: @step&.id).where.not(status: %w[completed failed blocked])
        if remaining.none?
          @execution.update!(status: "completed", completed_at: Time.current)
        end
      end

      # 6. Record execution succeeded audit
      record_audit_event!(
        event_type: "approval_execution_succeeded",
        actor_type: "system",
        actor_id: "tool_executor",
        approval: approval,
        metadata: {
          tool_name: @action_key,
          action_fingerprint: approval.action_fingerprint,
          result: tool_output
        }
      )

      ExecutionResult.new(
        status: "completed",
        result: tool_output,
        step: @step,
        approval: approval
      )
    rescue StandardError => e
      approval.update_columns(status: "failed") if approval.present? && approval.persisted?

      if @step.present?
        @step.update!(
          status: "failed",
          result: { "error" => "Execution failed: #{e.message}" }
        )
      end

      if @execution.present?
        @execution.update!(status: "failed", error_message: e.message)
      end

      record_audit_event!(
        event_type: "approval_execution_failed",
        actor_type: "system",
        actor_id: "tool_executor",
        approval: approval,
        metadata: {
          tool_name: @action_key,
          action_fingerprint: approval&.action_fingerprint,
          error: e.message
        }
      )

      ExecutionResult.new(
        status: "failed",
        step: @step,
        approval: approval,
        error_message: e.message
      )
    end

    private

    def validate_action!
      if @action_key.blank?
        raise ArgumentValidationError, "Action key cannot be blank"
      end

      unless @arguments.is_a?(Hash)
        raise ArgumentValidationError, "Tool arguments must be a Hash object"
      end
    end

    def handle_deny!(decision)
      if @step.present?
        @step.update!(
          status: "blocked",
          policy_decision: "deny",
          result: { "error" => "Blocked by policy engine: #{decision.reason}" }
        )
      end

      if @execution.present?
        @execution.update!(status: "blocked")
      end

      ExecutionResult.new(
        status: "blocked",
        decision: decision,
        step: @step,
        error_message: decision.reason
      )
    end

    def handle_require_approval!(decision)
      if @step.present?
        @step.update!(
          status: "waiting_approval",
          policy_decision: "require_approval"
        )
      end

      if @execution.present?
        @execution.update!(status: "paused")
      end

      approval = Approvals::Service.create_request(
        user: @user,
        task: @task,
        execution: @execution,
        agent_step: @step,
        action_key: @action_key,
        arguments: @arguments,
        decision: decision,
        expires_in: Approvals::ExpirationService.default_expiration_period
      )

      ExecutionResult.new(
        status: "paused",
        decision: decision,
        step: @step,
        approval: approval,
        error_message: decision.reason
      )
    end

    def handle_allow!(decision)
      unless decision.is_a?(Policies::Decision) && decision.allowed?
        raise PolicyBypassError, "Security Violation: Attempted to execute tool without valid ALLOW decision"
      end

      if @step.present?
        @step.update!(
          status: "running",
          policy_decision: "allow",
          started_at: Time.current
        )
      end

      if @execution.present? && @execution.status != "running"
        @execution.update!(status: "running")
      end

      # Execute verified tool dispatch (Simulated Safe Execution)
      tool_output = dispatch_tool!(@action_key, @arguments)

      if @step.present?
        @step.update!(
          status: "completed",
          result: tool_output,
          completed_at: Time.current
        )
      end

      ExecutionResult.new(
        status: "completed",
        result: tool_output,
        decision: decision,
        step: @step
      )
    end

    def handle_system_error!(err)
      Rails.logger.error("[VAISASTRAM Tool Execution Error] #{err.class}: #{err.message}")

      if @step.present?
        @step.update!(
          status: "failed",
          result: { "error" => "Execution failed: #{err.message}" }
        )
      end

      if @execution.present?
        @execution.update!(status: "failed", error_message: err.message)
      end

      ExecutionResult.new(
        status: "failed",
        step: @step,
        error_message: err.message
      )
    end

    # Safe simulated tool implementations (governed sandbox)
    def dispatch_tool!(action_key, args)
      case action_key
      when "retrieve_invoice", "lookup_invoice"
        invoice_id = args["invoice_id"] || args[:invoice_id] || "INV-100"
        {
          "invoice_id" => invoice_id,
          "vendor" => "Acme Corp",
          "amount" => 5000,
          "currency" => "INR",
          "line_items" => [
            { "description" => "Server Hosting", "amount" => 5000 }
          ],
          "status" => "retrieved"
        }
      when "verify_invoice"
        invoice_id = args["invoice_id"] || args[:invoice_id] || "INV-100"
        {
          "invoice_id" => invoice_id,
          "status" => "verified",
          "line_items_valid" => true,
          "vendor_verified" => true,
          "discrepancies_found" => 0
        }
      when "get_vendor"
        vendor_id = args["vendor_id"] || args[:vendor_id] || "VND-100"
        {
          "vendor_id" => vendor_id,
          "name" => "Acme Corp",
          "status" => "active",
          "kyc_verified" => true
        }
      when "prepare_payment"
        invoice_id = args["invoice_id"] || args[:invoice_id] || "INV-100"
        amount = args["amount"] || args[:amount] || 0
        {
          "voucher_id" => "VCH-#{SecureRandom.hex(4).upcase}",
          "invoice_id" => invoice_id,
          "amount" => amount,
          "currency" => "INR",
          "status" => "voucher_prepared"
        }
      else
        raise ExecutionError, "Unsupported tool handler for '#{action_key}'"
      end
    end

    def record_audit_event!(event_type:, actor_type:, actor_id:, approval: nil, metadata: {})
      AuditEvent.create!(
        user: @user,
        execution: @execution,
        agent_step: @step,
        approval: approval,
        event_type: event_type,
        actor_type: actor_type,
        actor_id: actor_id,
        occurred_at: Time.current,
        metadata: metadata
      )
    rescue StandardError => e
      Rails.logger.error("[VAISASTRAM Executor Audit Error] #{e.message}")
    end
  end
end
