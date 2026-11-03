module Replay
  class SecurityError < StandardError; end
  class UnauthorizedError < SecurityError; end
  class TamperError < SecurityError; end
end
