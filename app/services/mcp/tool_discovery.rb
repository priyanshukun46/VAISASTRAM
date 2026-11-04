module Mcp
  class ToolDiscovery
    attr_reader :server, :protocol_client

    def self.discover!(server, client: nil)
      new(server, client: client).discover!
    end

    def initialize(server, client: nil)
      @server = server
      @protocol_client = client || Mcp::ConnectionManager.protocol_client_for(server)
    end

    def discover!
      # Retrieve raw tools from external MCP server
      raw_tools = @protocol_client.list_tools
      discovered_records = []

      McpTool.transaction do
        raw_tools.each do |tool_hash|
          next unless tool_hash.is_a?(Hash)

          raw_name = tool_hash["name"].to_s.strip
          next if raw_name.blank?

          # Untrusted input defense: sanitize name and description
          clean_name = sanitize_tool_name(raw_name)
          clean_desc = tool_hash["description"].to_s.strip.truncate(1000)

          # Validate and sanitize input schema
          schema = tool_hash["inputSchema"].is_a?(Hash) ? tool_hash["inputSchema"] : { "type" => "object", "properties" => {} }
          schema_hash = McpTool.compute_schema_hash(schema)

          # Find or initialize existing record for this server
          mcp_tool = @server.mcp_tools.find_or_initialize_by(external_tool_name: clean_name)

          # Check if existing tool's schema changed
          if mcp_tool.persisted? && mcp_tool.schema_hash != schema_hash
            Rails.logger.warn("[MCP Tool Discovery] Schema changed for '#{clean_name}' on server '#{@server.name}'")
          end

          mcp_tool.assign_attributes(
            description: clean_desc,
            input_schema: schema,
            schema_hash: schema_hash,
            last_discovered_at: Time.current
          )

          # New tools are strictly disabled by default under fail-closed security mandate
          if mcp_tool.new_record?
            mcp_tool.enabled = false
            mcp_tool.policy_decision = "deny"
            mcp_tool.risk_classification = infer_risk(clean_name, clean_desc)
          end

          mcp_tool.save!
          discovered_records << mcp_tool
        end
      end

      # Record audit trail
      Audit::Recorder.record!(
        event_type: "mcp_tools_discovered",
        actor_type: "system",
        actor_id: "mcp_tool_discovery",
        user: @server.user,
        security_critical: false,
        metadata: {
          server_id: @server.id,
          server_name: @server.name,
          tools_count: discovered_records.size,
          tool_names: discovered_records.map(&:external_tool_name)
        }
      )

      discovered_records
    end

    private

    def sanitize_tool_name(name)
      # Allow only alphanumeric, underscore, hyphen
      name.gsub(/[^a-zA-Z0-9_-]/, "_")
    end

    def infer_risk(name, description)
      haystack = "#{name} #{description}".downcase
      if haystack.match?(/\b(delete|destroy|drop|remove|wipe|purge|execute|eval|shell|exec|admin)\b/)
        "critical"
      elsif haystack.match?(/\b(write|create|update|modify|edit|save|send|pay|transfer)\b/)
        "high"
      elsif haystack.match?(/\b(verify|check|validate|inspect|calculate|search)\b/)
        "medium"
      else
        "low"
      end
    end
  end
end
