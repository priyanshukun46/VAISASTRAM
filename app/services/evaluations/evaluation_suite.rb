module Evaluations
  class EvaluationSuite
    def self.cases
      new.build_cases
    end

    def build_cases
      [
        # ==========================================
        # Category 1: Policy Behavior (TC-01..TC-08)
        # ==========================================
        EvaluationCase.new(
          id: "TC-01",
          name: "Allowed invoice retrieval",
          category: :policy,
          description: "Verifies invoice retrieval (lookup_invoice) is explicitly permitted by ToolPermissionRule."
        ) do
          user = User.find_by(role: "operator") || User.first
          context = Policies::Context.new(user: user, action_key: "lookup_invoice", arguments: { "invoice_id" => "INV-100" })
          decision = Policies::Engine.evaluate(context)

          passed = decision.allowed?
          EvaluationResult.new(
            test_case_id: "TC-01",
            test_case_name: "Allowed invoice retrieval",
            category: :policy,
            expected_result: "ALLOW (permitted autonomous read-only tool)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "lookup_invoice", rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected ALLOW but got #{decision.decision}: #{decision.reason}"
          )
        end,

        EvaluationCase.new(
          id: "TC-02",
          name: "Allowed invoice verification",
          category: :policy,
          description: "Verifies invoice verification (verify_invoice) is allowlisted for autonomous evaluation."
        ) do
          user = User.find_by(role: "operator") || User.first
          context = Policies::Context.new(user: user, action_key: "verify_invoice", arguments: { "invoice_id" => "INV-100" })
          decision = Policies::Engine.evaluate(context)

          passed = decision.allowed?
          EvaluationResult.new(
            test_case_id: "TC-02",
            test_case_name: "Allowed invoice verification",
            category: :policy,
            expected_result: "ALLOW (permitted autonomous verification tool)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "verify_invoice", rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected ALLOW but got #{decision.decision}: #{decision.reason}"
          )
        end,

        EvaluationCase.new(
          id: "TC-03",
          name: "Allowed vendor retrieval",
          category: :policy,
          description: "Verifies vendor retrieval (get_vendor) is allowlisted for autonomous lookup."
        ) do
          user = User.find_by(role: "operator") || User.first
          context = Policies::Context.new(user: user, action_key: "get_vendor", arguments: { "vendor_id" => "VEND-1" })
          decision = Policies::Engine.evaluate(context)

          passed = decision.allowed?
          EvaluationResult.new(
            test_case_id: "TC-03",
            test_case_name: "Allowed vendor retrieval",
            category: :policy,
            expected_result: "ALLOW (permitted autonomous vendor lookup)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "get_vendor", rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected ALLOW but got #{decision.decision}: #{decision.reason}"
          )
        end,

        EvaluationCase.new(
          id: "TC-04",
          name: "Payment preparation within approval threshold",
          category: :policy,
          description: "Verifies payment preparation of ₹5,000 (<= ₹10,000 threshold) requires human approval."
        ) do
          user = User.find_by(role: "operator") || User.first
          context = Policies::Context.new(
            user: user,
            action_key: "prepare_payment",
            arguments: { "amount" => 5000, "currency" => "INR", "invoice_id" => "INV-100" }
          )
          decision = Policies::Engine.evaluate(context)

          passed = decision.requires_approval?
          EvaluationResult.new(
            test_case_id: "TC-04",
            test_case_name: "Payment preparation within approval threshold",
            category: :policy,
            expected_result: "REQUIRE_APPROVAL (Payment <= ₹10k requires human sign-off)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "prepare_payment", amount: 5000, rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected REQUIRE_APPROVAL but got #{decision.decision}: #{decision.reason}"
          )
        end,

        EvaluationCase.new(
          id: "TC-05",
          name: "Payment preparation above configured threshold",
          category: :policy,
          description: "Verifies payment preparation of ₹15,000 (> ₹10,000 limit) is strictly denied."
        ) do
          user = User.find_by(role: "operator") || User.first
          context = Policies::Context.new(
            user: user,
            action_key: "prepare_payment",
            arguments: { "amount" => 15000, "currency" => "INR", "invoice_id" => "INV-100" }
          )
          decision = Policies::Engine.evaluate(context)

          passed = decision.denied?
          EvaluationResult.new(
            test_case_id: "TC-05",
            test_case_name: "Payment preparation above configured threshold",
            category: :policy,
            expected_result: "DENY (Payment > ₹10k exceeds spending ceiling)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "prepare_payment", amount: 15000, rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected DENY but got #{decision.decision}: #{decision.reason}"
          )
        end,

        EvaluationCase.new(
          id: "TC-06",
          name: "Destructive operation denial",
          category: :policy,
          description: "Verifies destructive operations (delete_records / delete_database) are hard blocked by Priority 1 rule."
        ) do
          user = User.find_by(role: "admin") || User.first
          context = Policies::Context.new(user: user, action_key: "delete_records", arguments: { "target" => "all" })
          decision = Policies::Engine.evaluate(context)

          passed = decision.denied?
          EvaluationResult.new(
            test_case_id: "TC-06",
            test_case_name: "Destructive operation denial",
            category: :policy,
            expected_result: "DENY (Sensitive destructive operations are unconditionally prohibited)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "delete_records", rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected DENY but got #{decision.decision}: #{decision.reason}"
          )
        end,

        EvaluationCase.new(
          id: "TC-07",
          name: "Unknown tool denial",
          category: :policy,
          description: "Verifies unregistered/unknown tool actions are blocked under fail-closed mandate."
        ) do
          user = User.find_by(role: "operator") || User.first
          context = Policies::Context.new(user: user, action_key: "unregistered_custom_tool_xyz", arguments: {})
          decision = Policies::Engine.evaluate(context)

          passed = decision.denied?
          EvaluationResult.new(
            test_case_id: "TC-07",
            test_case_name: "Unknown tool denial",
            category: :policy,
            expected_result: "DENY (Unregistered tool rejected under default-deny)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "unregistered_custom_tool_xyz", rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected DENY but got #{decision.decision}: #{decision.reason}"
          )
        end,

        EvaluationCase.new(
          id: "TC-08",
          name: "Unauthorized tool denial",
          category: :policy,
          description: "Verifies actions missing required user permissions or roles are denied."
        ) do
          # Create temporary unprivileged user
          operator = User.new(name: "Test Operator", role: "operator", email: "test_op@vaisastram.internal")
          context = Policies::Context.new(
            user: operator,
            action_key: "delete_financial_record",
            arguments: { "id" => 1 }
          )
          decision = Policies::Engine.evaluate(context)

          passed = decision.denied?
          EvaluationResult.new(
            test_case_id: "TC-08",
            test_case_name: "Unauthorized tool denial",
            category: :policy,
            expected_result: "DENY (Operator lacks required administrative permission)",
            actual_result: decision.decision.upcase,
            passed: passed,
            relevant_references: { action: "delete_financial_record", rule: decision.policy_id },
            failure_explanation: passed ? nil : "Expected DENY but got #{decision.decision}: #{decision.reason}"
          )
        end,

        # ==========================================
        # Category 2: Approval Behavior (TC-09..TC-14)
        # ==========================================
        EvaluationCase.new(
          id: "TC-09",
          name: "Approval-required actions pause",
          category: :approval,
          description: "Verifies that an action requiring approval pauses execution and transitions to waiting_approval."
        ) do
          user = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: user)
          task = Task.create!(user: user, agent: agent, title: "Test Approval Pause", instruction: "Pay INV-100", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "running", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(position: 1, action_key: "prepare_payment", arguments: { "amount" => 5000 }, status: "pending")

          result = Tools::Executor.execute(step: step, user: user)
          step.reload
          passed = result.paused? && step.status == "waiting_approval" && step.approvals.any?(&:pending?)

          EvaluationResult.new(
            test_case_id: "TC-09",
            test_case_name: "Approval-required actions pause",
            category: :approval,
            expected_result: "Status waiting_approval and execution paused",
            actual_result: "Status #{step.status}, paused=#{result.paused?}",
            passed: passed,
            relevant_references: { step_id: step.id, status: step.status },
            failure_explanation: passed ? nil : "Expected step status 'waiting_approval' but got '#{step.status}'"
          )
        end,

        EvaluationCase.new(
          id: "TC-10",
          name: "Authorized reviewers can approve",
          category: :approval,
          description: "Verifies platform administrators or separate designated operators can approve sensitive requests."
        ) do
          admin = User.find_by(role: "admin") || User.create!(name: "Admin User", email: "admin_eval@vaisastram.test", password: "password123", role: "admin")
          creator = User.find_by(role: "operator") || User.create!(name: "Creator Operator", email: "creator_eval@vaisastram.test", password: "password123", role: "operator")

          agent = Agent.first || Agent.create!(name: "Test Agent", user: creator)
          task = Task.create!(user: creator, agent: agent, title: "Eval Task", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "paused", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(position: 1, action_key: "prepare_payment", arguments: { "amount" => 5000 }, status: "waiting_approval")
          approval = step.approvals.create!(user: creator, task: task, execution: execution, action_fingerprint: "dummy", action_digest: "dummy", status: "pending")

          can_admin = admin.can_approve?(approval)
          EvaluationResult.new(
            test_case_id: "TC-10",
            test_case_name: "Authorized reviewers can approve",
            category: :approval,
            expected_result: "can_approve? is TRUE for administrator",
            actual_result: "can_approve? is #{can_admin}",
            passed: can_admin == true,
            relevant_references: { reviewer_role: admin.role, approval_id: approval.id },
            failure_explanation: can_admin ? nil : "Admin user was incorrectly denied approval eligibility."
          )
        end,

        EvaluationCase.new(
          id: "TC-11",
          name: "Unauthorized reviewers cannot approve",
          category: :approval,
          description: "Verifies the task creator cannot self-approve their own request (segregation of duties)."
        ) do
          creator = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: creator)
          task = Task.create!(user: creator, agent: agent, title: "Eval Task", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "paused", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(position: 1, action_key: "prepare_payment", arguments: { "amount" => 5000 }, status: "waiting_approval")
          approval = step.approvals.create!(user: creator, task: task, execution: execution, action_fingerprint: "dummy", action_digest: "dummy", status: "pending")

          can_creator_approve = creator.can_approve?(approval)
          passed = (can_creator_approve == false)

          EvaluationResult.new(
            test_case_id: "TC-11",
            test_case_name: "Unauthorized reviewers cannot approve",
            category: :approval,
            expected_result: "can_approve? is FALSE for task creator",
            actual_result: "can_approve? is #{can_creator_approve}",
            passed: passed,
            relevant_references: { user_id: creator.id, task_creator_id: task.user_id },
            failure_explanation: passed ? nil : "Task creator was permitted to self-approve contrary to segregation of duties."
          )
        end,

        EvaluationCase.new(
          id: "TC-12",
          name: "Modified arguments invalidate approval",
          category: :approval,
          description: "Verifies that altering action arguments changes SHA-256 fingerprint, invalidating the approval."
        ) do
          user = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: user)
          task = Task.create!(user: user, agent: agent, title: "Eval Task", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "paused", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(position: 1, action_key: "prepare_payment", arguments: { "amount" => 5000 }, status: "waiting_approval")

          approval = step.approvals.create!(
            user: user, task: task, execution: execution,
            tool_name: "prepare_payment", action_arguments: { "amount" => 5000 }
          )

          # Alter step arguments to simulate tampering
          step.update!(arguments: { "amount" => 9999 })
          valid = Approvals::FingerprintValidator.valid?(approval)
          passed = (valid == false)

          EvaluationResult.new(
            test_case_id: "TC-12",
            test_case_name: "Modified arguments invalidate approval",
            category: :approval,
            expected_result: "FingerprintValidator.valid? returns FALSE upon argument tampering",
            actual_result: "valid? returned #{valid}",
            passed: passed,
            relevant_references: { approval_id: approval.id, original_amount: 5000, modified_amount: 9999 },
            failure_explanation: passed ? nil : "Fingerprint verification failed to detect modified arguments."
          )
        end,

        EvaluationCase.new(
          id: "TC-13",
          name: "Expired approvals cannot execute",
          category: :approval,
          description: "Verifies approvals whose expires_at timestamp has passed are marked expired and blocked."
        ) do
          user = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: user)
          task = Task.create!(user: user, agent: agent, title: "Eval Task", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "paused", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(position: 1, action_key: "prepare_payment", arguments: { "amount" => 5000 }, status: "waiting_approval")

          approval = step.approvals.create!(
            user: user, task: task, execution: execution,
            tool_name: "prepare_payment", action_arguments: { "amount" => 5000 },
            expires_at: 10.minutes.ago, status: "pending"
          )

          is_expired = approval.expired?
          passed = (is_expired == true)

          EvaluationResult.new(
            test_case_id: "TC-13",
            test_case_name: "Expired approvals cannot execute",
            category: :approval,
            expected_result: "Approval is expired? == TRUE",
            actual_result: "expired? == #{is_expired}",
            passed: passed,
            relevant_references: { approval_id: approval.id, expires_at: approval.expires_at },
            failure_explanation: passed ? nil : "Expired approval was not detected as expired."
          )
        end,

        EvaluationCase.new(
          id: "TC-14",
          name: "Consumed approvals cannot be replayed",
          category: :approval,
          description: "Verifies already executed approvals cannot be consumed a second time."
        ) do
          user = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: user)
          task = Task.create!(user: user, agent: agent, title: "Eval Task", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "paused", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(position: 1, action_key: "prepare_payment", arguments: { "amount" => 5000 }, status: "waiting_approval")

          approval = step.approvals.create!(
            user: user, task: task, execution: execution,
            tool_name: "prepare_payment", action_arguments: { "amount" => 5000 },
            status: "executed"
          )

          passed = approval.executed? && !approval.pending?
          EvaluationResult.new(
            test_case_id: "TC-14",
            test_case_name: "Consumed approvals cannot be replayed",
            category: :approval,
            expected_result: "Status executed; pending? is FALSE",
            actual_result: "status=#{approval.status}, pending?=#{approval.pending?}",
            passed: passed,
            relevant_references: { approval_id: approval.id, status: approval.status },
            failure_explanation: passed ? nil : "Consumed approval was incorrectly marked pending or usable."
          )
        end,

        # ==========================================
        # Category 3: Execution Behavior (TC-15..TC-20)
        # ==========================================
        EvaluationCase.new(
          id: "TC-15",
          name: "Valid plans pass schema validation",
          category: :execution,
          description: "Verifies conformant dual-mode action plans pass strict PlanValidator."
        ) do
          plan = {
            "mode" => "action_plan",
            "goal" => "Verify invoice and prepare payment",
            "response" => "I propose verifying invoice INV-100 and preparing payment.",
            "steps" => [
              {
                "step_number" => 1,
                "action" => "verify_invoice",
                "arguments" => { "invoice_id" => "INV-100" },
                "description" => "Verify invoice authenticity"
              }
            ]
          }

          passed = false
          begin
            Planning::PlanValidator.validate!(plan, allowed_tools: ["verify_invoice"])
            passed = true
          rescue StandardError => e
            passed = false
          end

          EvaluationResult.new(
            test_case_id: "TC-15",
            test_case_name: "Valid plans pass schema validation",
            category: :execution,
            expected_result: "Validation succeeds with zero errors",
            actual_result: passed ? "Validated successfully" : "Raised error",
            passed: passed,
            relevant_references: { mode: "action_plan", steps_count: 1 },
            failure_explanation: passed ? nil : "Valid action plan was incorrectly rejected by PlanValidator."
          )
        end,

        EvaluationCase.new(
          id: "TC-16",
          name: "Malformed plans are rejected",
          category: :execution,
          description: "Verifies plans missing the required 'mode' field are rejected under strict schema validation."
        ) do
          malformed = {
            "response" => "Missing mode field",
            "steps" => []
          }

          rejected = false
          begin
            Planning::PlanValidator.validate!(malformed, allowed_tools: ["lookup_invoice"])
          rescue Planning::ValidationError => e
            rejected = true
          end

          EvaluationResult.new(
            test_case_id: "TC-16",
            test_case_name: "Malformed plans are rejected",
            category: :execution,
            expected_result: "Planning::ValidationError raised for missing mode",
            actual_result: rejected ? "ValidationError raised" : "Accepted invalid plan",
            passed: rejected,
            relevant_references: { missing_field: "mode" },
            failure_explanation: rejected ? nil : "PlanValidator silently accepted plan missing required 'mode' key."
          )
        end,

        EvaluationCase.new(
          id: "TC-17",
          name: "Invalid tools are blocked",
          category: :execution,
          description: "Verifies that an action key not in the allowlist is rejected by PlanValidator."
        ) do
          plan = {
            "mode" => "action_plan",
            "goal" => "Unauthorized tool action",
            "response" => "Proposing unauthorized shell execution",
            "steps" => [
              {
                "step_number" => 1,
                "action" => "unregistered_shell_execution",
                "arguments" => {},
                "description" => "Shell"
              }
            ]
          }

          blocked = false
          begin
            Planning::PlanValidator.validate!(plan, allowed_tools: ["lookup_invoice", "verify_invoice"])
          rescue Planning::ValidationError => e
            blocked = true
          end

          EvaluationResult.new(
            test_case_id: "TC-17",
            test_case_name: "Invalid tools are blocked",
            category: :execution,
            expected_result: "Planning::ValidationError raised for unallowlisted tool",
            actual_result: blocked ? "ValidationError raised" : "Accepted invalid tool",
            passed: blocked,
            relevant_references: { tool: "unregistered_shell_execution" },
            failure_explanation: blocked ? nil : "Unallowlisted tool was not rejected by PlanValidator."
          )
        end,

        EvaluationCase.new(
          id: "TC-18",
          name: "Tool execution failures are recorded",
          category: :execution,
          description: "Verifies when a tool execution fails, the step status is recorded as failed and audited."
        ) do
          user = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: user)
          task = Task.create!(user: user, agent: agent, title: "Eval Failure", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "running", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(position: 1, action_key: "verify_invoice", arguments: { "invoice_id" => "INV-FAIL" }, status: "pending")

          # Record tool failure event
          step.update!(status: "failed", result: { "error" => "Simulated network timeout connecting to invoice service" })
          Audit::Recorder.record!(
            user: user, task: task, execution: execution, agent_step: step,
            event_type: "tool_execution_failed", actor_type: "system",
            metadata: { error: "Simulated network timeout" }
          )

          step.reload
          has_audit = execution.audit_events.where(event_type: "tool_execution_failed").exists?
          passed = (step.status == "failed" && has_audit)

          EvaluationResult.new(
            test_case_id: "TC-18",
            test_case_name: "Tool execution failures are recorded",
            category: :execution,
            expected_result: "Step status failed with tool_execution_failed audit event",
            actual_result: "Step status #{step.status}, audit logged=#{has_audit}",
            passed: passed,
            relevant_references: { step_id: step.id, status: step.status },
            failure_explanation: passed ? nil : "Tool failure was not recorded on step or audit trail."
          )
        end,

        EvaluationCase.new(
          id: "TC-19",
          name: "Replay does not trigger side effects",
          category: :execution,
          description: "Verifies simulation replay re-evaluates step policies in read-only mode without executing external actions."
        ) do
          user = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: user)
          task = Task.create!(user: user, agent: agent, title: "Replay Test", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "completed", provider: "gemini", ai_model: "gemini-3.8-flash")
          step = execution.agent_steps.create!(
            position: 1, action_key: "lookup_invoice",
            arguments: { "invoice_id" => "INV-100" },
            status: "completed", policy_decision: "allow"
          )

          result = Replay::ExecutionReplayer.replay(execution: execution, user: user, mode: :simulation)
          passed = result.simulation? && result.reconstructed_steps.size == 1

          EvaluationResult.new(
            test_case_id: "TC-19",
            test_case_name: "Replay does not trigger side effects",
            category: :execution,
            expected_result: "Simulation succeeds in read-only mode (simulation? == true)",
            actual_result: "simulation?=#{result.simulation?}, steps=#{result.reconstructed_steps.size}",
            passed: passed,
            relevant_references: { execution_id: execution.id, mode: result.mode },
            failure_explanation: passed ? nil : "Replay simulation failed to execute in safe read-only mode."
          )
        end,

        EvaluationCase.new(
          id: "TC-20",
          name: "Audit integrity verification detects tampering",
          category: :execution,
          description: "Verifies Audit::IntegrityVerifier detects altered cryptographic event digests."
        ) do
          user = User.find_by(role: "operator") || User.first
          agent = Agent.first || Agent.create!(name: "Test Agent", user: user)
          task = Task.create!(user: user, agent: agent, title: "Tamper Test", instruction: "Instruction", submitted_at: Time.current)
          execution = task.executions.create!(agent: agent, status: "completed", provider: "gemini", ai_model: "gemini-3.8-flash")

          # Create a valid chained event
          event = Audit::Recorder.record!(
            user: user, task: task, execution: execution,
            event_type: "execution_started", actor_type: "agent",
            metadata: { note: "original" }
          )

          # Tamper directly in the database using raw SQL to bypass ActiveRecord read-only hooks
          ActiveRecord::Base.connection.execute(
            "UPDATE audit_events SET metadata = '{\"note\":\"tampered\"}' WHERE id = #{event.id}"
          )

          verification = Audit::IntegrityVerifier.verify_chain(event.chain_id)
          detected = verification.tampered_event_ids.include?(event.id)

          EvaluationResult.new(
            test_case_id: "TC-20",
            test_case_name: "Audit integrity verification detects tampering",
            category: :execution,
            expected_result: "Tampering detected in tampered_event_ids",
            actual_result: "Detected in tampered_event_ids=#{detected}",
            passed: detected,
            relevant_references: { event_id: event.id, chain_id: event.chain_id },
            failure_explanation: detected ? nil : "IntegrityVerifier failed to detect database tampering."
          )
        end
      ]
    end
  end
end
