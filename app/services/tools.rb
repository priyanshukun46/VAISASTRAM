module Tools
  class ExecutionError < StandardError; end
  class PolicyBlockedError < ExecutionError; end
  class ApprovalRequiredError < ExecutionError; end
  class ArgumentValidationError < ExecutionError; end
  class PolicyBypassError < SecurityError; end
end
