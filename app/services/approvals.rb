module Approvals
  class Error < StandardError; end
  class UnauthorizedReviewerError < Error; end
  class DuplicateDecisionError < Error; end
  class ExpiredError < Error; end
  class FingerprintMismatchError < Error; end
  class PolicyRejectionError < Error; end
  class InvalidActionError < Error; end
end
