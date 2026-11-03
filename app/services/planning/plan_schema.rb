module Planning
  class PlanSchema
    MAX_STEPS = 10
    MIN_STEPS = 1

    ALLOWED_TOP_LEVEL_KEYS = %w[goal summary steps].freeze
    ALLOWED_STEP_KEYS = %w[step_number action arguments description].freeze

    def self.json_schema(available_tools: [])
      schema = {
        type: "object",
        properties: {
          goal: {
            type: "string",
            description: "Concise statement of the overall goal to be accomplished."
          },
          summary: {
            type: "string",
            description: "High-level summary of the proposed multi-step execution plan."
          },
          steps: {
            type: "array",
            description: "Sequential list of proposed tool actions (minimum 1, maximum 10).",
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
        required: ["goal", "summary", "steps"]
      }

      if available_tools.present?
        schema[:properties][:steps][:items][:properties][:action][:enum] = available_tools
      end

      schema
    end
  end
end
