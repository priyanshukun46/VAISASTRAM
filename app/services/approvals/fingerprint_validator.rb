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

        # Compare canonicalized arguments (ignoring internal metadata keys like _mcp_* added during approval binding)
        clean_step_args = (step.arguments || {}).reject { |k, _| k.to_s.start_with?("_") }
        clean_appr_args = (arguments || {}).reject { |k, _| k.to_s.start_with?("_") }
        canonical_step_args = Policies::Fingerprint.canonicalize_arguments(clean_step_args)
        canonical_appr_args = Policies::Fingerprint.canonicalize_arguments(clean_appr_args)

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

      # 5. MCP-specific configuration & schema integrity check
      if tool_name.to_s.start_with?("mcp.")
        mcp_tool = McpTool.find_by(namespaced_tool_key: tool_name)
        if mcp_tool.nil? || mcp_tool.mcp_server.nil?
          @approval.update_columns(status: "invalidated") if @approval.persisted?
          raise Approvals::FingerprintMismatchError,
            "MCP tool '#{tool_name}' or its server no longer exists. Approval has been invalidated."
        end

        bound_config_ver = arguments["_mcp_config_version"]
        bound_schema_hash = arguments["_mcp_schema_hash"]

        if bound_config_ver.present? && bound_config_ver.to_s != mcp_tool.mcp_server.configuration_version.to_s
          @approval.update_columns(status: "invalidated") if @approval.persisted?
          raise Approvals::FingerprintMismatchError,
            "MCP server configuration has changed since approval was requested (version #{bound_config_ver} -> #{mcp_tool.mcp_server.configuration_version}). Approval has been invalidated."
        end

        if bound_schema_hash.present? && bound_schema_hash.to_s != mcp_tool.schema_hash.to_s
          @approval.update_columns(status: "invalidated") if @approval.persisted?
          raise Approvals::FingerprintMismatchError,
            "MCP tool schema has changed since approval was requested. Approval has been invalidated."
        end
      end

      true
    end
  end
end
