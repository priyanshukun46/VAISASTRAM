class ExpireApprovalsJob < ApplicationJob
  queue_as :default

  def perform
    Approvals::ExpirationService.expire_stale!
  end
end
