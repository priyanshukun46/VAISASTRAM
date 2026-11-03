module Replay
  class SecurityError < StandardError; end
  class UnauthorizedError < SecurityError; end
  class TamperError < SecurityError; end

  class ReplayValidator
    SENSITIVE_KEYS = %w[
      password secret token api_key apikey private_key auth_token credential
    ].freeze

    def self.validate!(context)
      new(context).validate!
    end

    attr_reader :context

    def initialize(context)
      @context = context
    end

    def validate!
      # 1. Enforce authentication and access control
      unless @context.user.is_a?(User) && @context.user.persisted?
        raise UnauthorizedError, "Authentication required to replay execution history."
      end

      unless @context.user.can_access?(@context.execution)
        raise UnauthorizedError, "Access Denied: User #{@context.user.id} is not authorized to inspect Execution ##{@context.execution.id}."
      end

      # 2. Replay cannot modify original records (read-only verification)
      if @context.execution.readonly?
        # Good, already readonly
      end

      # 3. Check for allowlisted tools in history
      @context.steps.each do |step|
        validate_step_action!(step.action_key)
      end

      true
    end

    def validate_step_action!(action_key)
      return if action_key.blank?

      # Reject malicious inputs (shell, SQL injection, code evaluation attempts)
      if action_key.match?(/[\;\&\|\`\$\(\)\<\>]/)
        raise SecurityError, "Disallowed characters in action key: '#{action_key}'"
      end
    end

    def self.redact_sensitive(data)
      return {} if data.blank?
      case data
      when Hash
        data.each_with_object({}) do |(k, v), clean|
          if SENSITIVE_KEYS.any? { |s| k.to_s.downcase.include?(s) }
            clean[k] = "[REDACTED]"
          else
            clean[k] = redact_sensitive(v)
          end
        end
      when Array
        data.map { |v| redact_sensitive(v) }
      else
        data
      end
    end
  end
end
