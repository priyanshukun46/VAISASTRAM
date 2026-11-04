module Approvals
  class Service
    def self.create_request(**kwargs)
      new.create_request(**kwargs)
    end

    def self.approve(**kwargs)
      new.approve(**kwargs)
    end

    def self.reject(**kwargs)
      new.reject(**kwargs)
    end

    def create_request(user:, task:, execution: nil, agent_step: nil, action_key:, arguments: {}, decision: nil, expires_in: Approvals::ExpirationService.default_expiration_period)
      # Bind MCP server identity, configuration version, and schema hash if an MCP tool
      effective_args = (arguments || {}).deep_dup
      if action_key.to_s.start_with?("mcp.")
        mcp_tool = McpTool.find_by(namespaced_tool_key: action_key)
        if mcp_tool.present? && mcp_tool.mcp_server.present?
          effective_args["_mcp_server_id"] = mcp_tool.mcp_server.id.to_s
          effective_args["_mcp_config_version"] = mcp_tool.mcp_server.configuration_version.to_s
          effective_args["_mcp_schema_hash"] = mcp_tool.schema_hash.to_s
        end
      end

      fingerprint = Policies::Fingerprint.generate(
        user: user,
        task: task,
        action_key: action_key,
        arguments: effective_args
      )

      # Check for existing active pending request for the identical action
      existing = if agent_step.present?
        Approval.where(agent_step: agent_step, status: "pending", action_fingerprint: fingerprint).first
      else
        Approval.where(task: task, status: "pending", action_fingerprint: fingerprint).first
      end

      if existing.present? && !existing.expired?
        return existing
      end

      approval = Approval.create!(
        user: user,
        task: task,
        execution: execution || agent_step&.execution,
        agent_step: agent_step,
        tool_name: action_key.to_s.strip.downcase,
        action_arguments: effective_args,
        action_fingerprint: fingerprint,
        action_digest: fingerprint,
        policy_decision_reference: decision&.policy_id || "policy_engine",
        status: "pending",
        requested_at: Time.current,
        expires_at: Time.current + expires_in
      )

      record_audit!(
        event_type: "approval_requested",
        approval: approval,
        actor_type: "policy_engine",
        actor_id: decision&.policy_id || "policy_engine",
        metadata: {
          tool_name: approval.tool_name,
          action_fingerprint: fingerprint,
          policy_id: decision&.policy_id,
          reason: decision&.reason,
          expires_at: approval.expires_at.iso8601
        }
      )

      if action_key.to_s.start_with?("mcp.")
        record_audit!(
          event_type: "mcp_tool_approval_requested",
          approval: approval,
          actor_type: "policy_engine",
          actor_id: decision&.policy_id || "policy_engine",
          metadata: {
            tool_name: approval.tool_name,
            action_fingerprint: fingerprint,
            reason: decision&.reason
          }
        )
      end

      approval
    end

    def approve(approval_id:, reviewer:)
      # 1. Enforce authenticated human reviewer
      validate_reviewer!(reviewer)

      approval = nil

      # 2. Row-level transaction lock to prevent duplicate decisions or race conditions
      Approval.transaction do
        approval = Approval.lock("FOR UPDATE").find_by(id: approval_id)
        raise Approvals::Error, "Approval ##{approval_id} not found" unless approval

        # 3. Duplicate and replay protection
        unless approval.status == "pending"
          raise Approvals::DuplicateDecisionError,
            "Approval ##{approval.id} has already been decided: current status is '#{approval.status}'"
        end

        # 4. Check expiration during the transaction
        if approval.expired?
          raise Approvals::ExpiredError, "Approval request ##{approval.id} has expired and cannot be approved"
        end

        # 5. Enforce reviewer authorization
        unless reviewer.can_approve?(approval)
          raise Approvals::UnauthorizedReviewerError,
            "User #{reviewer.id} (#{reviewer.role}) is not authorized to approve this action"
        end

        # 6. Action fingerprint binding verification
        unless Approvals::FingerprintValidator.valid?(approval)
          raise Approvals::FingerprintMismatchError,
            "Action parameters have been modified since approval was requested; approval invalidated."
        end

        # 7. Independent Policy Revalidation before execution
        context = Policies::Context.new(
          user: approval.effective_user,
          agent: approval.effective_execution&.agent,
          task: approval.effective_task,
          execution: approval.effective_execution,
          agent_step: approval.agent_step,
          action_key: approval.effective_tool_name,
          arguments: approval.effective_arguments
        )

        decision = Policies::Engine.evaluate(context)

        if decision.denied?
          raise Approvals::PolicyRejectionError, "Policy revalidation denied execution: #{decision.reason}"
        end

        # 8. Mark approval as approved
        approval.update!(
          status: "approved",
          reviewer: reviewer,
          reviewed_at: Time.current
        )

        record_audit!(
          event_type: "approval_approved",
          approval: approval,
          actor_type: "user",
          actor_id: reviewer.id.to_s,
          metadata: {
            reviewer_id: reviewer.id,
            reviewer_name: reviewer.name,
            reviewer_role: reviewer.role,
            action_fingerprint: approval.action_fingerprint,
            tool_name: approval.effective_tool_name
          }
        )
      end

      # 9. Resume execution via Tools::Executor outside the decision lock
      exec_result = Tools::Executor.resume_approved(approval, reviewer: reviewer)

      Approvals::Decision.new(
        status: "executed",
        approval: approval,
        execution_result: exec_result
      )
    rescue Approvals::ExpiredError
      if approval
        approval.update_columns(status: "expired")
        Approvals::ExpirationService.expire_single!(approval)
      end
      raise
    rescue Approvals::FingerprintMismatchError
      if approval
        approval.update_columns(status: "invalidated")
        approval.agent_step&.update_columns(status: "blocked", result: { "error" => "Approval invalidated: parameters modified" })
        approval.effective_execution&.update_columns(status: "blocked")

        record_audit!(
          event_type: "approval_invalidated",
          approval: approval,
          actor_type: "user",
          actor_id: reviewer.id.to_s,
          metadata: {
            reason: "Fingerprint validation failed: action arguments, tool name, or context were modified"
          }
        )
      end
      raise
    rescue Approvals::PolicyRejectionError => e
      if approval
        approval.update_columns(status: "failed")
        approval.agent_step&.update_columns(status: "blocked", result: { "error" => "Policy DENIED on revalidation: #{e.message}" })
        approval.effective_execution&.update_columns(status: "blocked")

        record_audit!(
          event_type: "approval_invalidated",
          approval: approval,
          actor_type: "policy_engine",
          actor_id: "policy_engine",
          metadata: { reason: e.message }
        )
      end
      raise
    end

    def reject(approval_id:, reviewer:, reason: nil)
      validate_reviewer!(reviewer)

      approval = nil
      rejection_note = reason.presence || "Action rejected by reviewer #{reviewer.name}"

      Approval.transaction do
        approval = Approval.lock("FOR UPDATE").find_by(id: approval_id)
        raise Approvals::Error, "Approval ##{approval_id} not found" unless approval

        unless approval.status == "pending"
          raise Approvals::DuplicateDecisionError,
            "Approval ##{approval.id} has already been decided: current status is '#{approval.status}'"
        end

        if approval.expired?
          raise Approvals::ExpiredError, "Approval request ##{approval.id} has expired and cannot be rejected"
        end

        unless reviewer.can_approve?(approval) || reviewer.can_access?(approval)
          raise Approvals::UnauthorizedReviewerError,
            "User #{reviewer.id} (#{reviewer.role}) is not authorized to reject this action"
        end

        approval.update!(
          status: "rejected",
          reviewer: reviewer,
          reviewed_at: Time.current,
          rejection_reason: rejection_note
        )

        if approval.agent_step.present?
          approval.agent_step.update_columns(
            status: "rejected",
            result: { "rejected_by" => reviewer.name, "reason" => rejection_note }
          )
        end

        execution = approval.effective_execution
        if execution.present? && %w[running paused].include?(execution.status)
          execution.update_columns(status: "blocked", error_message: "Action rejected by #{reviewer.name}")
        end

        record_audit!(
          event_type: "approval_rejected",
          approval: approval,
          actor_type: "user",
          actor_id: reviewer.id.to_s,
          metadata: {
            reviewer_id: reviewer.id,
            reviewer_name: reviewer.name,
            reviewer_role: reviewer.role,
            rejection_reason: rejection_note,
            action_fingerprint: approval.action_fingerprint,
            tool_name: approval.effective_tool_name
          }
        )
      end

      Approvals::Decision.new(
        status: "rejected",
        approval: approval
      )
    rescue Approvals::ExpiredError
      if approval
        approval.update_columns(status: "expired")
        Approvals::ExpirationService.expire_single!(approval)
      end
      raise
    end

    private

    def validate_reviewer!(reviewer)
      unless reviewer.is_a?(User) && reviewer.persisted?
        raise Approvals::UnauthorizedReviewerError, "Reviewer must be an authenticated User"
      end

      # Reject AI agents or background jobs
      if reviewer.respond_to?(:agent?) && reviewer.agent?
        raise Approvals::UnauthorizedReviewerError, "AI agents cannot act as human reviewers"
      end
    end

    def record_audit!(event_type:, approval:, actor_type:, actor_id:, metadata: {})
      Audit::Recorder.record!(
        user: approval.effective_user,
        task: approval.effective_task,
        execution: approval.effective_execution,
        agent_step: approval.agent_step,
        approval: approval,
        event_type: event_type,
        actor_type: actor_type,
        actor_id: actor_id,
        tool_name: approval.effective_tool_name,
        action_fingerprint: approval.action_fingerprint,
        status: approval.status,
        occurred_at: Time.current,
        security_critical: true,
        metadata: metadata.merge(
          approval_id: approval.id,
          task_id: approval.effective_task&.id,
          execution_id: approval.effective_execution&.id
        )
      )
    rescue StandardError => e
      Rails.logger.error("[VAISASTRAM Approvals Audit Error] #{event_type}: #{e.message}")
      raise
    end
  end
end
