require_relative "errors"

module Mcp
  class ProtocolClient
    PROTOCOL_VERSION = "2024-11-05".freeze
    CLIENT_INFO = { name: "VAISASTRAM", version: "2.0.0" }.freeze

    attr_reader :transport, :server, :server_info, :capabilities, :negotiated_version

    def initialize(transport, server: nil)
      @transport = transport
      @server = server || transport.server
      @request_id = 0
      @server_info = {}
      @capabilities = {}
      @negotiated_version = nil
      @initialized = false
    end

    def initialize_session!
      res = send_rpc("initialize", {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {
          roots: { listChanged: true },
          sampling: {}
        },
        clientInfo: CLIENT_INFO
      })

      result = res["result"]
      unless result.is_a?(Hash)
        raise Mcp::ProtocolError, "MCP server did not return a valid result object during initialization"
      end

      @negotiated_version = result["protocolVersion"] || PROTOCOL_VERSION
      @server_info = result["serverInfo"] || {}
      @capabilities = result["capabilities"] || {}

      # Send notifications/initialized notification
      send_notification("notifications/initialized")
      @initialized = true

      {
        protocol_version: @negotiated_version,
        server_info: @server_info,
        capabilities: @capabilities
      }
    end

    def list_tools
      initialize_session! unless @initialized

      res = send_rpc("tools/list", {})
      result = res["result"]

      unless result.is_a?(Hash) && result["tools"].is_a?(Array)
        raise Mcp::ProtocolError, "Malformed tools/list response: expected result.tools array"
      end

      result["tools"]
    end

    def call_tool(tool_name, arguments = {})
      initialize_session! unless @initialized

      res = send_rpc("tools/call", {
        name: tool_name.to_s,
        arguments: arguments || {}
      })

      result = res["result"]
      unless result.is_a?(Hash)
        raise Mcp::ToolExecutionError, "Malformed tools/call response from MCP server: expected result object"
      end

      if result["isError"] == true
        err_msg = extract_content_text(result["content"]) || "Tool execution returned isError: true"
        raise Mcp::ToolExecutionError, "MCP Tool '#{tool_name}' error: #{err_msg}"
      end

      {
        "content" => result["content"] || [],
        "text" => extract_content_text(result["content"]),
        "is_error" => false,
        "metadata" => result["metadata"] || {}
      }
    end

    def ping
      send_rpc("ping", {})
      true
    rescue StandardError
      false
    end

    private

    def next_id
      @request_id += 1
    end

    def send_rpc(method, params = {})
      payload = {
        jsonrpc: "2.0",
        id: next_id,
        method: method.to_s,
        params: params
      }

      response = @transport.send_request(payload)

      if response.nil? || !response.is_a?(Hash)
        raise Mcp::ProtocolError, "Empty or invalid response received from MCP server"
      end

      if response.key?("error")
        err = response["error"]
        msg = err.is_a?(Hash) ? "#{err['message']} (Code: #{err['code']})" : err.to_s
        raise Mcp::ProtocolError, "MCP server returned error on '#{method}': #{msg}"
      end

      response
    end

    def send_notification(method, params = {})
      payload = {
        jsonrpc: "2.0",
        method: method.to_s,
        params: params
      }

      # Notifications do not expect a response in JSON-RPC
      begin
        @transport.send_request(payload, timeout: 2)
      rescue Mcp::TimeoutError
        # Ignored for fire-and-forget notifications
      rescue StandardError => e
        Rails.logger.warn("[MCP Protocol] Notification '#{method}' warning: #{e.message}")
      end
    end

    def extract_content_text(content_array)
      return nil unless content_array.is_a?(Array)

      texts = content_array.filter_map do |item|
        item["text"] if item.is_a?(Hash) && item["type"] == "text"
      end
      texts.join("\n").presence
    end
  end
end
