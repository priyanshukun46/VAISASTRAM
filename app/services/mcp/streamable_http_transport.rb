require "net/http"
require "json"
require "uri"

module Mcp
  class StreamableHttpTransport
    MAX_RESPONSE_BYTES = 5 * 1024 * 1024 # 5 MB
    MAX_REDIRECTS = 3

    attr_reader :server, :endpoint_uri

    def initialize(server)
      @server = server
      @endpoint_uri = URI.parse(server.endpoint_url.to_s.strip)
    end

    def start
      # Pre-flight SSRF check
      ssrf_check = Mcp::Security::SsrfGuard.check(server.endpoint_url, allow_local: server.allow_local_connections?)
      unless ssrf_check.safe?
        raise Mcp::SsrfError, "SSRF Check Failed: #{ssrf_check.reason}"
      end
      self
    end

    def send_request(payload, timeout: nil)
      start
      req_timeout = timeout || server.request_timeout
      conn_timeout = server.connection_timeout

      json_str = payload.is_a?(String) ? payload : payload.to_json
      current_uri = @endpoint_uri
      redirect_count = 0

      loop do
        # Defense-in-depth: Re-check URI on every hop (redirect safety)
        ssrf_check = Mcp::Security::SsrfGuard.check(current_uri.to_s, allow_local: server.allow_local_connections?)
        unless ssrf_check.safe?
          raise Mcp::SsrfError, "SSRF Check Failed on redirect: #{ssrf_check.reason}"
        end

        http = Net::HTTP.new(current_uri.host, current_uri.port)
        http.open_timeout = conn_timeout
        http.read_timeout = req_timeout

        if current_uri.scheme == "https"
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        request = Net::HTTP::Post.new(current_uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json, text/event-stream"
        request["User-Agent"] = "VAISASTRAM-MCP/2.0"

        # Apply authentication headers from server configuration
        server.auth_headers.each do |k, v|
          request[k] = v
        end

        request.body = json_str

        begin
          response = http.request(request)
        rescue Net::OpenTimeout, Net::ReadTimeout => e
          raise Mcp::TimeoutError, "Streamable HTTP request to '#{current_uri}' timed out: #{e.message}"
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
          raise Mcp::ConnectionError, "Connection refused to '#{current_uri}': #{e.message}"
        rescue StandardError => e
          raise Mcp::ConnectionError, "HTTP request failed: #{e.message}"
        end

        # Handle redirects safely
        if [301, 302, 307, 308].include?(response.code.to_i)
          redirect_count += 1
          if redirect_count > MAX_REDIRECTS
            raise Mcp::ConnectionError, "Exceeded maximum redirect count (#{MAX_REDIRECTS})"
          end

          location = response["Location"]
          if location.blank?
            raise Mcp::ConnectionError, "Redirect missing Location header"
          end

          new_uri = URI.join(current_uri.to_s, location)
          # Strict security: prohibit downgrade from HTTPS to HTTP
          if current_uri.scheme == "https" && new_uri.scheme != "https"
            raise Mcp::SecurityError, "Insecure protocol downgrade prohibited in redirect (#{current_uri} -> #{new_uri})"
          end

          current_uri = new_uri
          next
        end

        if response.code.to_i == 401 || response.code.to_i == 403
          raise Mcp::AuthenticationError, "Authentication failed with status #{response.code}: #{response.body.truncate(100)}"
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise Mcp::ConnectionError, "Remote MCP server returned HTTP #{response.code}: #{response.body.truncate(100)}"
        end

        if response.body.to_s.bytesize > MAX_RESPONSE_BYTES
          raise Mcp::SecurityError, "Response size exceeds maximum limit of #{MAX_RESPONSE_BYTES / (1024 * 1024)}MB"
        end

        return parse_http_response(response)
      end
    end

    def close
      # HTTP is stateless; no persistent socket to close
    end

    def active?
      true
    end

    private

    def parse_http_response(response)
      body = response.body.to_s.strip

      # Check for Server-Sent Events stream (Streamable HTTP spec)
      content_type = response["Content-Type"].to_s.downcase
      if content_type.include?("text/event-stream") || body.start_with?("data:", "event:")
        # Parse last JSON message in SSE event stream
        last_json = nil
        body.each_line do |line|
          line = line.strip
          if line.start_with?("data:")
            data_payload = line.sub(/\Adata:\s*/, "").strip
            begin
              last_json = JSON.parse(data_payload)
            rescue JSON::ParserError; end
          end
        end

        return last_json if last_json.present?
      end

      begin
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Mcp::ProtocolError, "Invalid JSON-RPC response from Streamable HTTP: #{e.message} (Raw: #{body.truncate(100)})"
      end
    end
  end
end
