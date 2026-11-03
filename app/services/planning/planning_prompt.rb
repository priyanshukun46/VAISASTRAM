module Planning
  class PlanningPrompt
    def self.build_system_prompt(agent:, tools: [])
      tools_description = format_tools(tools)

      <<~PROMPT
        You are an autonomous AI planning agent operating within VAISASTRAM.
        Your principle: "AI proposes. Ruby decides."

        You must decompose the user's natural-language instruction into a structured multi-step execution plan.
        You only PROPOSE steps; an independent Ruby policy engine will validate, authorize, or block each step prior to any execution.

        AVAILABLE TOOLS:
        #{tools_description}

        STRICT PLANNING RULES:
        1. Propose ONLY actions from the available tools list above.
        2. Never invent tool names, external URLs, shell commands, SQL queries, or arbitrary code.
        3. Do not include risk classifications, permission checks, or authorization decisions. Ruby decides risk and authorization.
        4. Steps must be sequential, starting at step_number 1 up to a maximum of #{PlanSchema::MAX_STEPS} steps.
        5. Every step's "arguments" MUST be a JSON object matching the tool's input schema.
        6. You MUST return ONLY valid JSON matching the exact schema requested. Do not include introductory text, conversational remarks, or markdown fences.

        AGENT CONFIGURATION:
        Name: #{agent.name}
        Description: #{agent.description}
      PROMPT
    end

    def self.build_user_prompt(task:)
      <<~PROMPT
        TASK TO ACCOMPLISH:
        "#{task.instruction}"

        Generate a complete, sequential JSON plan proposing the necessary tool actions to fulfill this instruction safely and accurately.
      PROMPT
    end

    private

    def self.format_tools(tools)
      return "No tools available." if tools.blank?

      tools.map do |t|
        schema_json = t.input_schema.present? ? t.input_schema.to_json : "{}"
        "- Tool key: `#{t.key}` (#{t.name})\n  Description: #{t.description}\n  Input Schema: #{schema_json}"
      end.join("\n\n")
    end
  end
end
