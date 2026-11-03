module Approvals
  class FingerprintValidator
    def self.validate!(approval)
      new(approval).validate!
    end

    def self.valid?(approval)
      new(approval).valid?
    end

    attr_reader :approval

    def initialize(approval)
      @approval = approval
    end

    def valid?
      validate!
      true
    rescue Approvals::FingerprintMismatchError
      false
    end

    def validate!
      unless @approval.is_a?(Approval)
        raise Approvals::FingerprintMismatchError, "Invalid approval object provided for fingerprint validation"
      end

      # 1. Ensure required bound elements are present
      user = @approval.effective_user
      task = @approval.effective_task
      tool_name = @approval.effective_tool_name
      arguments = @approval.effective_arguments

      if tool_name.blank?
        raise Approvals::FingerprintMismatchError, "Tool name is missing from approval record"
      end

      # 2. Check bound agent_step if attached
      if @approval.agent_step.present?
        step = @approval.agent_step

        if step.action_key.to_s.strip.downcase != tool_name.to_s.strip.downcase
          raise Approvals::FingerprintMismatchError,
            "Action mismatch: step action '#{step.action_key}' does not match approval tool '#{tool_name}'"
        end

        # Compare canonicalized arguments
        canonical_step_args = Policies::Fingerprint.canonicalize_arguments(step.arguments)
        canonical_appr_args = Policies::Fingerprint.canonicalize_arguments(arguments)

        if canonical_step_args != canonical_appr_args
          raise Approvals::FingerprintMismatchError,
            "Argument mismatch between step arguments and approval arguments"
        end
      end

      # 3. Recalculate deterministic action fingerprint
      recalculated_fingerprint = Policies::Fingerprint.generate(
        user: user,
        task: task,
        action_key: tool_name,
        arguments: arguments
      )

      # 4. Compare with bound fingerprint stored on approval
      stored_fingerprint = @approval.action_fingerprint.presence || @approval.action_digest

      if stored_fingerprint.blank?
        raise Approvals::FingerprintMismatchError, "Approval record has no stored action fingerprint"
      end

      unless ActiveSupport::SecurityUtils.secure_compare(recalculated_fingerprint, stored_fingerprint)
        raise Approvals::FingerprintMismatchError,
          "Action fingerprint mismatch: arguments or execution context have been modified since approval was requested."
      end

      true
    end
  end
end
