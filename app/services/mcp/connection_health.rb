module Mcp
  class ConnectionHealth
    attr_reader :server, :result

    def self.check!(server, client: nil)
      new(server, client: client).check!
    end

    def initialize(server, client: nil)
      @server = server
      @client = client
    end

    def check!
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client = @client || Mcp::ConnectionManager.protocol_client_for(@server)

      begin
        handshake = client.initialize_session!
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

        @server.update!(
          status: "connected",
          protocol_version: handshake[:protocol_version],
          server_info: handshake[:server_info],
          capabilities: handshake[:capabilities],
          last_connected_at: Time.current,
          last_health_check_at: Time.current,
          error_message: nil
        )

        Audit::Recorder.record!(
          event_type: "mcp_server_connected",
          actor_type: "system",
          actor_id: "mcp_connection_health",
          user: @server.user,
          security_critical: false,
          metadata: {
            server_id: @server.id,
            server_name: @server.name,
            transport_type: @server.transport_type,
            handshake_duration_ms: duration_ms,
            protocol_version: handshake[:protocol_version]
          }
        )

        { success: true, duration_ms: duration_ms, handshake: handshake }
      rescue StandardError => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

        @server.update!(
          status: "failed",
          last_health_check_at: Time.current,
          error_message: e.message.truncate(500)
        )

        Audit::Recorder.record!(
          event_type: "mcp_server_connection_failed",
          actor_type: "system",
          actor_id: "mcp_connection_health",
          user: @server.user,
          security_critical: true,
          metadata: {
            server_id: @server.id,
            server_name: @server.name,
            transport_type: @server.transport_type,
            error_class: e.class.name,
            error_message: e.message
          }
        )

        { success: false, duration_ms: duration_ms, error: e.message }
      end
    end
  end
end
