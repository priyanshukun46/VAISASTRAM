module Planning
  class PlanSchema
    MAX_STEPS = 10
    MIN_STEPS = 1

    ALLOWED_TOP_LEVEL_KEYS = %w[
      response
      requires_action
      goal
      summary
      steps
      clarification_needed
      explanation
    ].freeze

    ALLOWED_STEP_KEYS = %w[step_number action arguments description].freeze

    def self.json_schema(available_tools: [])
      schema = {
        type: "object",
        properties: {
          response: {
            type: "string",
            description: "Short, human-readable message for the chat interface. Acknowledge user request, explain planned steps, ask clarifying questions if details are missing, or explain why an action cannot be planned. MUST NEVER claim or imply that actions have already been executed."
          },
          requires_action: {
            type: "boolean",
            description: "True if tool action steps are proposed; false if clarifying information is needed, the request cannot be planned, or it is a conversational inquiry."
          },
          goal: {
            type: "string",
            description: "Concise statement of the overall goal to be accomplished or topic of conversation."
          },
          summary: {
            type: "string",
            description: "High-level summary of the proposed multi-step execution plan or conversational status."
          },
          clarification_needed: {
            type: "string",
            description: "Details on what essential information is missing to formulate a safe plan."
          },
          explanation: {
            type: "string",
            description: "Clear explanation if the requested action cannot be planned with available tools."
          },
          steps: {
            type: "array",
            description: "Sequential list of proposed tool actions (minimum 1 when requires_action is true; empty array if requires_action is false).",
            items: {
              type: "object",
              properties: {
                step_number: {
                  type: "integer",
                  description: "1-based sequential index (1, 2, 3...)."
                },
                action: {
                  type: "string",
                  description: "The allowlisted tool key to invoke."
                },
                arguments: {
                  type: "object",
                  description: "Key-value input parameters for the tool action."
                },
                description: {
                  type: "string",
                  description: "Brief explanation of why this step is proposed."
                }
              },
              required: ["step_number", "action", "arguments", "description"]
            }
          }
        },
        required: ["goal", "response", "steps"]
      }

      if available_tools.present?
        schema[:properties][:steps][:items][:properties][:action][:enum] = available_tools
      end

      schema
    end
  end
end
