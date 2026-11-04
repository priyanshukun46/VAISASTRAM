module Mcp
  module Errors
    class McpError < StandardError; end
    class ConnectionError < McpError; end
    class TimeoutError < McpError; end
    class ProtocolError < McpError; end
    class AuthenticationError < McpError; end
    class SecurityError < McpError; end
    class SsrfError < SecurityError; end
    class CommandExecutionError < SecurityError; end
    class ToolNotFoundError < McpError; end
    class ToolExecutionError < McpError; end
    class SchemaValidationError < McpError; end
  end

  # Aliases for direct Mcp:: namespace access
  McpError = Errors::McpError
  ConnectionError = Errors::ConnectionError
  TimeoutError = Errors::TimeoutError
  ProtocolError = Errors::ProtocolError
  AuthenticationError = Errors::AuthenticationError
  SecurityError = Errors::SecurityError
  SsrfError = Errors::SsrfError
  CommandExecutionError = Errors::CommandExecutionError
  ToolNotFoundError = Errors::ToolNotFoundError
  ToolExecutionError = Errors::ToolExecutionError
  SchemaValidationError = Errors::SchemaValidationError
end
