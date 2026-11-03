class UpdateAgentIdentityToVaisastramAgent < ActiveRecord::Migration[8.0]
  def up
    Agent.where(name: ["Financial Operations Agent", "Master Financial Agent", "Invoice Auditor"]).update_all(
      name: "VAISASTRAM Agent",
      description: "General-purpose governed autonomous AI agent platform with independent Ruby policy enforcement, conversational reasoning, and allowlisted domain tools."
    )
  end

  def down
    Agent.where(name: "VAISASTRAM Agent").update_all(
      name: "Financial Operations Agent",
      description: "Autonomous financial and accounting workflow agent with strict policy governance."
    )
  end
end
