class SecurityMailerPreview < ActionMailer::Preview
  def policy_blocked
    user = User.first || User.new(name: "Operator Jane", email: "jane@vaisastram.internal")
    task = Task.first || Task.new(id: 88, user: user, title: "Export Customer Data")
    execution = Execution.first || Execution.new(id: 602, task: task)
    step = AgentStep.new(id: 1, execution: execution, action_key: "export_raw_pii", status: "blocked")

    decision = Struct.new(:reason, :policy_id).new("Action violates GDPR/SOC2 data sovereignty policies", "pol_data_protection_01")
    SecurityMailer.policy_blocked(step: step, execution: execution, decision: decision)
  end

  def security_alert
    user = User.first || User.new(name: "Compliance Officer", email: "auditor@vaisastram.internal")
    SecurityMailer.security_alert(user, details: {
      type: "FINGERPRINT_TAMPERING_DETECTED",
      message: "An attempt to execute an unverified action with modified arguments was blocked.",
      action_fingerprint: "bf3d18e5476a0c88319e"
    })
  end

  def account_security_notification
    user = User.first || User.new(name: "Operator Jane", email: "jane@vaisastram.internal")
    SecurityMailer.account_security_notification(user, details: {
      event: "Password reset token requested",
      ip_address: "203.0.113.195"
    })
  end
end
