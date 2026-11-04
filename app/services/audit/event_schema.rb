module Audit
  class EventSchema
    SENSITIVE_KEYS = %w[
      password secret token api_key apikey private_key auth_token credential
      authorization private_key_pem bearer access_token refresh_token
    ].freeze

    TASK_EVENTS = %w[
      task_created task_started task_completed task_failed task_cancelled task_submitted
    ].freeze

    PLANNING_EVENTS = %w[
      plan_generated plan_validated plan_rejected plan_modified planning_failed conversation_replied
    ].freeze

    POLICY_EVENTS = %w[
      policy_evaluated policy_allowed policy_approval_required policy_denied policy_modified
    ].freeze

    TOOL_EVENTS = %w[
      tool_requested tool_validated tool_execution_started tool_execution_succeeded
      tool_execution_failed tool_execution_blocked
    ].freeze

    APPROVAL_EVENTS = %w[
      approval_requested approval_approved approval_rejected approval_expired
      approval_invalidated approval_consumed approval_execution_succeeded approval_execution_failed
    ].freeze

    PROVIDER_EVENTS = %w[
      ai_provider_selected ai_provider_failed ai_provider_fallback_used
    ].freeze

    MCP_EVENTS = %w[
      mcp_server_created mcp_server_connected mcp_server_connection_failed
      mcp_server_disconnected mcp_tools_discovered mcp_tool_enabled
      mcp_tool_disabled mcp_tool_invocation_requested mcp_tool_policy_evaluated
      mcp_tool_approval_requested mcp_tool_invocation_succeeded
      mcp_tool_invocation_failed mcp_server_configuration_changed
      mcp_server_removed
    ].freeze

    ALL_EVENT_TYPES = (
      TASK_EVENTS + PLANNING_EVENTS + POLICY_EVENTS +
      TOOL_EVENTS + APPROVAL_EVENTS + PROVIDER_EVENTS + MCP_EVENTS
    ).uniq.freeze

    ACTOR_TYPES = %w[user agent policy_engine system].freeze

    def self.sanitize_metadata(meta)
      return {} if meta.blank? || !meta.is_a?(Hash)

      meta.each_with_object({}) do |(key, value), clean_hash|
        key_str = key.to_s.strip.downcase
        if SENSITIVE_KEYS.any? { |s| key_str.include?(s) }
          clean_hash[key.to_s] = "[REDACTED]"
        elsif value.is_a?(Hash)
          clean_hash[key.to_s] = sanitize_metadata(value)
        elsif value.is_a?(Array)
          clean_hash[key.to_s] = value.map { |v| v.is_a?(Hash) ? sanitize_metadata(v) : v }
        elsif value.is_a?(String) && value.length > 2000
          # Protect against unbounded prompt / provider blob dumps
          clean_hash[key.to_s] = "#{value.first(500)}... [TRUNCATED #{value.length} BYTES]"
        else
          clean_hash[key.to_s] = value
        end
      end
    end
  end
end
