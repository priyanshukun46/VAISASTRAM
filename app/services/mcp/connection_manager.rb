module Mcp
  class ConnectionManager
    class << self
      attr_accessor :mock_client_factory

      def transport_for(server)
        instance.transport_for(server)
      end

      def protocol_client_for(server)
        if mock_client_factory.present?
          return mock_client_factory.call(server)
        end
        instance.protocol_client_for(server)
      end

      def disconnect(server)
        instance.disconnect(server)
      end

      def shutdown_all
        instance.shutdown_all
      end

      def reset!
        instance.shutdown_all
      end
    end

    def self.instance
      @instance ||= new
    end

    def initialize
      @transports = {}
      @clients = {}
      @mutex = Mutex.new
    end

    def transport_for(server)
      @mutex.synchronize do
        key = server.id || server.server_identifier

        existing = @transports[key]
        return existing if existing.present? && existing.active?

        transport = if server.stdio?
          Mcp::StdioTransport.new(server)
        else
          Mcp::StreamableHttpTransport.new(server)
        end

        @transports[key] = transport
        transport
      end
    end

    def protocol_client_for(server)
      @mutex.synchronize do
        key = server.id || server.server_identifier

        # Return existing client if transport is active
        existing_client = @clients[key]
        transport = transport_for_unlocked(server)

        if existing_client.present? && transport.active?
          return existing_client
        end

        client = Mcp::ProtocolClient.new(transport, server: server)
        @clients[key] = client
        client
      end
    end

    def disconnect(server)
      @mutex.synchronize do
        key = server.id || server.server_identifier
        transport = @transports.delete(key)
        @clients.delete(key)

        transport&.close
      end
    end

    def shutdown_all
      @mutex.synchronize do
        @transports.each_value(&:close)
        @transports.clear
        @clients.clear
      end
    end

    private

    def transport_for_unlocked(server)
      key = server.id || server.server_identifier
      existing = @transports[key]
      return existing if existing.present? && existing.active?

      transport = if server.stdio?
        Mcp::StdioTransport.new(server)
      else
        Mcp::StreamableHttpTransport.new(server)
      end

      @transports[key] = transport
      transport
    end
  end
end
