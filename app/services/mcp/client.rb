require_relative "errors"

module Mcp
  class Client
    class << self
      def connect(server)
        new(server).connect
      end

      def discover_tools(server)
        new(server).discover_tools
      end

      def call_tool(server, tool_name, arguments = {})
        new(server).call_tool(tool_name, arguments)
      end

      def disconnect(server)
        new(server).disconnect
      end

      def check_health(server)
        new(server).check_health
      end
    end

    attr_reader :server

    def initialize(server)
      @server = server
    end

    def connect
      Mcp::ConnectionHealth.check!(server)
    end

    def discover_tools
      Mcp::ToolDiscovery.discover!(server)
    end

    def check_health
      Mcp::ConnectionHealth.check!(server)
    end

    def disconnect
      Mcp::ConnectionManager.disconnect(server)
      server.update!(status: "disconnected")

      Audit::Recorder.record!(
        event_type: "mcp_server_disconnected",
        actor_type: "system",
        actor_id: "mcp_client",
        user: server.user,
        security_critical: false,
        metadata: {
          server_id: server.id,
          server_name: server.name
        }
      )

      true
    end

    def call_tool(tool_name, arguments = {})
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      protocol_client = Mcp::ConnectionManager.protocol_client_for(server)

      Audit::Recorder.record!(
        event_type: "mcp_tool_invocation_requested",
        actor_type: "system",
        actor_id: "mcp_client",
        user: server.user,
        tool_name: "#{server.server_identifier}.#{tool_name}",
        metadata: {
          server_id: server.id,
          tool_name: tool_name,
          arguments_keys: arguments.keys
        }
      )

      begin
        result = protocol_client.call_tool(tool_name, arguments)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

        # Update last invoked and invocation count on McpTool record
        mcp_tool = server.mcp_tools.find_by(external_tool_name: tool_name)
        if mcp_tool.present?
          mcp_tool.increment!(:invocation_count)
          mcp_tool.update_columns(last_invoked_at: Time.current)
        end

        Audit::Recorder.record!(
          event_type: "mcp_tool_invocation_succeeded",
          actor_type: "system",
          actor_id: "mcp_client",
          user: server.user,
          tool_name: "#{server.server_identifier}.#{tool_name}",
          metadata: {
            server_id: server.id,
            tool_name: tool_name,
            duration_ms: duration_ms
          }
        )

        result
      rescue StandardError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

        Audit::Recorder.record!(
          event_type: "mcp_tool_invocation_failed",
          actor_type: "system",
          actor_id: "mcp_client",
          user: server.user,
          tool_name: "#{server.server_identifier}.#{tool_name}",
          security_critical: true,
          metadata: {
            server_id: server.id,
            tool_name: tool_name,
            error_class: e.class.name,
            error_message: e.message,
            duration_ms: duration_ms
          }
        )

        raise
      end
    end
  end
end
