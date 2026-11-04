require "open3"
require "json"
require "timeout"

module Mcp
  class StdioTransport
    attr_reader :server, :pid, :stderr_log

    def initialize(server)
      @server = server
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thr = nil
      @pid = nil
      @mutex = Mutex.new
      @stderr_log = []
    end

    def start
      @mutex.synchronize do
        return if active?

        # Strict defense-in-depth executable verification
        cmd = server.command.to_s.strip
        cmd_base = File.basename(cmd).downcase

        if McpServer::DISALLOWED_COMMANDS.include?(cmd_base) || cmd.include?("..")
          raise Mcp::CommandExecutionError, "Prohibited executable: #{cmd}"
        end

        env = server.env_hash.dup
        # Restrict environment exposure: pass clean environment with PATH preserved
        env["PATH"] ||= ENV["PATH"]

        begin
          @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(env, cmd, *server.args_array)
          @pid = @wait_thr.pid

          # Start background thread to capture stderr diagnostics separately
          @stderr_thread = Thread.new do
            begin
              @stderr.each_line do |line|
                @stderr_log << line.strip
                @stderr_log.shift if @stderr_log.size > 100 # Keep last 100 lines
              end
            rescue IOError, StandardError
              # Pipe closed
            end
          end
        rescue Errno::ENOENT => e
          raise Mcp::ConnectionError, "Executable '#{cmd}' not found on system: #{e.message}"
        rescue StandardError => e
          raise Mcp::ConnectionError, "Failed to launch STDIO MCP server '#{server.name}': #{e.message}"
        end
      end
      self
    end

    def send_request(payload, timeout: nil)
      start unless active?
      req_timeout = timeout || server.request_timeout

      @mutex.synchronize do
        json_str = payload.is_a?(String) ? payload : payload.to_json

        begin
          @stdin.puts(json_str)
          @stdin.flush
        rescue IOError, Errno::EPIPE => e
          close
          raise Mcp::ConnectionError, "STDIO write failed (pipe broken): #{e.message}"
        end

        # Non-blocking line-delimited JSON-RPC read with strict timeout
        ready = IO.select([@stdout], nil, nil, req_timeout)
        unless ready
          close
          raise Mcp::TimeoutError, "STDIO MCP server timed out after #{req_timeout}s waiting for response"
        end

        line = @stdout.gets
        if line.nil?
          diagnostics = @stderr_log.last(5).join(" | ")
          close
          raise Mcp::ConnectionError, "STDIO MCP server closed stdout unexpectedly. Stderr: #{diagnostics.presence || 'None'}"
        end

        begin
          JSON.parse(line.strip)
        rescue JSON::ParserError => e
          raise Mcp::ProtocolError, "Invalid JSON-RPC response from STDIO: #{e.message} (Raw: #{line.truncate(100)})"
        end
      end
    end

    def active?
      @wait_thr.present? && @wait_thr.alive?
    end

    def close
      @mutex.synchronize do
        begin
          @stdin&.close unless @stdin&.closed?
        rescue IOError; end

        begin
          @stdout&.close unless @stdout&.closed?
        rescue IOError; end

        begin
          @stderr&.close unless @stderr&.closed?
        rescue IOError; end

        if @pid.present?
          begin
            Process.kill("TERM", @pid)
            # Give process up to 1 second to terminate gracefully
            Timeout.timeout(1) { Process.wait(@pid) }
          rescue Timeout::Error
            begin
              Process.kill("KILL", @pid)
              Process.wait(@pid) rescue nil
            rescue StandardError; end
          rescue Errno::ESRCH, Errno::ECHILD; end
        end

        @wait_thr = nil
        @pid = nil
      end
    end
  end
end
