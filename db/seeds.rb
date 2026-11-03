# Seed users for VAISASTRAM governance platform (Devise authentication)

admin = User.find_or_initialize_by(email: "admin@vaisastram.internal")
admin.name = "Lead Operator"
admin.role = "admin"
admin.password = "vaisastram2026"
admin.password_confirmation = "vaisastram2026"
admin.save!

operator = User.find_or_initialize_by(email: "operator@vaisastram.internal")
operator.name = "Operations Analyst"
operator.role = "operator"
operator.password = "vaisastram2026"
operator.password_confirmation = "vaisastram2026"
operator.save!

auditor = User.find_or_initialize_by(email: "auditor@vaisastram.internal")
auditor.name = "Compliance Auditor"
auditor.role = "auditor"
auditor.password = "vaisastram2026"
auditor.password_confirmation = "vaisastram2026"
auditor.save!

# Seed Allowlisted Tools
tools_data = [
  {
    key: "lookup_invoice",
    name: "Invoice Lookup",
    description: "Fetches invoice details and line items by invoice identifier.",
    risk_level: "low",
    required_permission: "invoice:read",
    input_schema: {
      type: "object",
      properties: { invoice_id: { type: "string", description: "Invoice reference code (e.g. INV-100)" } },
      required: ["invoice_id"]
    }
  },
  {
    key: "verify_invoice",
    name: "Invoice Verification",
    description: "Validates line items, mathematical sums, and vendor status.",
    risk_level: "low",
    required_permission: "invoice:verify",
    input_schema: {
      type: "object",
      properties: { invoice_id: { type: "string" }, expected_total: { type: "number" } },
      required: ["invoice_id"]
    }
  },
  {
    key: "prepare_payment",
    name: "Simulated Payment Preparation",
    description: "Generates a pre-approved disbursement voucher for authorized payment.",
    risk_level: "high",
    required_permission: "payment:prepare",
    input_schema: {
      type: "object",
      properties: { invoice_id: { type: "string" }, amount: { type: "number" }, currency: { type: "string", default: "INR" } },
      required: ["invoice_id", "amount"]
    }
  },
  {
    key: "delete_records",
    name: "Delete Financial Records",
    description: "Restricted administrative deletion of ledger or tax records.",
    risk_level: "critical",
    required_permission: "admin:delete_records",
    input_schema: {
      type: "object",
      properties: { target: { type: "string" } },
      required: ["target"]
    }
  }
]

tools_data.each do |t_data|
  tool = Tool.find_or_initialize_by(key: t_data[:key])
  tool.assign_attributes(t_data.merge(enabled: true))
  tool.save!
end

# Seed Initial Governance Policies
policies_data = [
  {
    name: "Allow Invoice Lookup",
    description: "Permits autonomous retrieval of invoice metadata.",
    action_key: "lookup_invoice",
    effect: "allow",
    priority: 10,
    conditions: {},
    enabled: true
  },
  {
    name: "Allow Invoice Verification",
    description: "Permits automated cross-check of line items and calculations.",
    action_key: "verify_invoice",
    effect: "allow",
    priority: 20,
    conditions: {},
    enabled: true
  },
  {
    name: "Block Excessive Payments",
    description: "Automatically blocks any payment preparation exceeding ₹10,000 threshold.",
    action_key: "prepare_payment",
    effect: "deny",
    priority: 30,
    conditions: { "amount_gt" => 10000 },
    enabled: true
  },
  {
    name: "Require Approval for Standard Payment",
    description: "Demands human operator signature before preparing payments <= ₹10,000.",
    action_key: "prepare_payment",
    effect: "require_approval",
    priority: 40,
    conditions: { "amount_lte" => 10000 },
    enabled: true
  },
  {
    name: "Explicitly Block Record Deletion",
    description: "Hard block on any attempt by an agent to destroy financial records.",
    action_key: "delete_records",
    effect: "deny",
    priority: 1,
    conditions: {},
    enabled: true
  }
]

policies_data.each do |p_data|
  policy = Policy.find_or_initialize_by(name: p_data[:name], user_id: nil)
  policy.assign_attributes(p_data)
  policy.save!
end

# Seed Sample Autonomous Agent
agent = Agent.find_or_initialize_by(name: "VAISASTRAM Agent", user: admin)
agent.description = "General-purpose governed autonomous AI agent platform with independent Ruby policy enforcement, conversational reasoning, and allowlisted domain tools."
agent.status = "active"
agent.configuration = {
  allowed_tools: ["lookup_invoice", "verify_invoice", "prepare_payment"],
  model: "gemini-2.5-pro",
  max_steps: 6
}
agent.save!

puts "✅ Phase 2 Seeds Loaded:"
puts "   - Users: #{User.count}"
puts "   - Tools: #{Tool.count}"
puts "   - Policies: #{Policy.count}"
puts "   - Agents: #{Agent.count}"
