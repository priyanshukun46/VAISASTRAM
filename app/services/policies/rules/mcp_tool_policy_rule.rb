module Policies
  module Rules
    class McpToolPolicyRule < BaseRule
      def initialize
        super(
          rule_id: "mcp_tool_policy_rule",
          name: "MCP Server & Tool Policy Guard",
          description: "Evaluates administrative policy decisions for dynamically registered MCP tools.",
          priority: 15
        )
      end

      def evaluate(context)
        return nil unless context.action_key.to_s.start_with?("mcp.")

        mcp_tool = McpTool.find_by(namespaced_tool_key: context.action_key)

        # 1. Reject unknown or unregistered MCP tool
        if mcp_tool.nil? || mcp_tool.mcp_server.nil?
          return Decision.deny(
            policy_id: rule_id,
            reason: "Unknown or unregistered MCP tool '#{context.action_key}' is denied under fail-closed security mandate",
            matched_conditions: { registered: false },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        server = mcp_tool.mcp_server

        # 2. Reject if tool or server is disabled
        unless server.enabled? && mcp_tool.enabled?
          return Decision.deny(
            policy_id: rule_id,
            reason: "MCP tool '#{context.action_key}' or server '#{server.name}' is disabled",
            matched_conditions: { server_enabled: server.enabled?, tool_enabled: mcp_tool.enabled? },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        # 3. Reject if server is not connected / healthy
        unless server.connected?
          return Decision.deny(
            policy_id: rule_id,
            reason: "MCP server '#{server.name}' is not connected (current status: #{server.status})",
            matched_conditions: { server_status: server.status },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end

        # Record MCP-specific policy audit event
        Audit::Recorder.record!(
          event_type: "mcp_tool_policy_evaluated",
          actor_type: "policy_engine",
          actor_id: rule_id,
          user: context.user,
          task: context.task,
          execution: context.execution,
          tool_name: context.action_key,
          action_fingerprint: context.action_fingerprint,
          policy_decision: mcp_tool.policy_decision,
          security_critical: true,
          metadata: {
            server_id: server.id,
            server_name: server.name,
            tool_name: mcp_tool.external_tool_name,
            policy_decision: mcp_tool.policy_decision,
            risk_classification: mcp_tool.risk_classification,
            configuration_version: server.configuration_version,
            schema_hash: mcp_tool.schema_hash
          }
        )

        # 4. Evaluate configured policy decision on the tool
        case mcp_tool.policy_decision
        when "allow"
          Decision.allow(
            policy_id: rule_id,
            reason: "MCP tool '#{mcp_tool.external_tool_name}' is explicitly configured to ALLOW execution",
            matched_conditions: {
              server_id: server.id,
              policy: "allow",
              configuration_version: server.configuration_version,
              schema_hash: mcp_tool.schema_hash
            },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        when "require_approval"
          Decision.require_approval(
            policy_id: rule_id,
            reason: "MCP tool '#{mcp_tool.external_tool_name}' requires human operator approval prior to execution",
            matched_conditions: {
              server_id: server.id,
              policy: "require_approval",
              configuration_version: server.configuration_version,
              schema_hash: mcp_tool.schema_hash
            },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        else # Default to DENY
          Decision.deny(
            policy_id: rule_id,
            reason: "MCP tool '#{mcp_tool.external_tool_name}' is set to DENY under fail-closed security mandate",
            matched_conditions: {
              server_id: server.id,
              policy: "deny",
              configuration_version: server.configuration_version,
              schema_hash: mcp_tool.schema_hash
            },
            action_fingerprint: context.action_fingerprint,
            context: context
          )
        end
      end
    end
  end
end
