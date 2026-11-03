module Planning
  # PlanNormalizer handles standardizing valid model responses across diverse LLM providers
  # (Ollama, Gemini, Groq, OpenRouter).
  #
  # Safe Default Determination Policy:
  # - If a model returns canonical "conversation" or "action_plan" (or known aliases/casing),
  #   it is normalized directly to the canonical symbol string.
  # - If a model response is completely invalid (not a Hash, missing required fields, or unrecognized mode),
  #   PlanNormalizer does NOT silently invent a valid mode; it preserves the invalid value or nil,
  #   allowing PlanValidator to reject it under strict schema enforcement.
  # - If an otherwise valid model response omitted the "mode" key:
  #   * When steps are empty [] and clarification/explanation/no-action is indicated => safe default is "conversation".
  #   * When steps contains tool items and goal is present => safe default is "action_plan".
  class PlanNormalizer
    CONVERSATION_MODE = "conversation".freeze
    ACTION_PLAN_MODE = "action_plan".freeze
    VALID_MODES = [CONVERSATION_MODE, ACTION_PLAN_MODE].freeze

    # Recognized valid model response aliases
    CONVERSATION_ALIASES = %w[
      conversation conversational chat dialogue inquiry general message
    ].freeze

    ACTION_PLAN_ALIASES = %w[
      action_plan action-plan action_plans actions action plan tools
    ].freeze

    def self.normalize(plan_data)
      new.normalize(plan_data)
    end

    def normalize(plan_data)
      return {} unless plan_data.is_a?(Hash)

      raw_mode = plan_data["mode"] || plan_data[:mode]
      raw_steps = plan_data["steps"] || plan_data[:steps]

      # 1. Normalize Mode
      mode = normalize_mode(raw_mode, plan_data, raw_steps)

      response_text = (plan_data["response"] || plan_data[:response]).to_s.strip
      summary = (plan_data["summary"] || plan_data[:summary]).to_s.strip.presence || response_text

      result = {}
      result["mode"] = mode if mode.present?

      if plan_data.key?("response") || plan_data.key?(:response)
        result["response"] = response_text
      end

      if mode == CONVERSATION_MODE
        result["requires_action"] = false
        if plan_data.key?("goal") || plan_data.key?(:goal)
          result["goal"] = (plan_data["goal"] || plan_data[:goal]).presence
        end
        result["steps"] = []
      elsif mode == ACTION_PLAN_MODE
        result["requires_action"] = true
        if plan_data.key?("goal") || plan_data.key?(:goal)
          result["goal"] = (plan_data["goal"] || plan_data[:goal]).to_s.strip
        end

        if raw_steps.is_a?(Array)
          result["steps"] = raw_steps.map do |step|
            next unless step.is_a?(Hash)
            {
              "step_number" => (step["step_number"] || step[:step_number]).to_i,
              "action" => (step["action"] || step[:action]).to_s.strip,
              "arguments" => normalize_arguments(step["arguments"] || step[:arguments]),
              "description" => (step["description"] || step[:description]).to_s.strip
            }
          end.compact
        elsif plan_data.key?("steps") || plan_data.key?(:steps)
          result["steps"] = raw_steps
        end
      else
        # For legacy or unrecognized modes, preserve raw fields for PlanValidator inspection
        result["goal"] = (plan_data["goal"] || plan_data[:goal]).to_s.strip if plan_data.key?("goal") || plan_data.key?(:goal)
        result["steps"] = raw_steps if plan_data.key?("steps") || plan_data.key?(:steps)
      end

      result["summary"] = summary if summary.present?

      if (clarification = (plan_data["clarification_needed"] || plan_data[:clarification_needed]).to_s.strip).present?
        result["clarification_needed"] = clarification
      end

      if (explanation = (plan_data["explanation"] || plan_data[:explanation]).to_s.strip).present?
        result["explanation"] = explanation
      end

      result
    end

    private

    def normalize_mode(raw_mode, plan_data, raw_steps)
      if raw_mode.present?
        cleaned = raw_mode.to_s.strip
        normalized = cleaned.downcase.tr("- ", "_")
        return CONVERSATION_MODE if CONVERSATION_ALIASES.include?(normalized)
        return ACTION_PLAN_MODE if ACTION_PLAN_ALIASES.include?(normalized)

        # Preserve unrecognized mode string so PlanValidator will reject it
        return cleaned
      end

      # Safe default determination when mode is omitted:
      # Only apply safe default if the response has an unambiguous structure.
      has_goal = (plan_data["goal"] || plan_data[:goal]).present?
      has_steps = raw_steps.is_a?(Array) && raw_steps.any?
      has_clarification = plan_data["clarification_needed"].present? || plan_data[:clarification_needed].present?
      has_explanation = plan_data["explanation"].present? || plan_data[:explanation].present?
      has_explicit_no_action = plan_data["requires_action"] == false || plan_data[:requires_action] == false

      if has_clarification || has_explanation || has_explicit_no_action
        CONVERSATION_MODE
      elsif has_steps && has_goal
        ACTION_PLAN_MODE
      elsif raw_steps.is_a?(Array) && raw_steps.empty? && !has_goal
        CONVERSATION_MODE
      else
        # Do not silently invent a mode if the model output is ambiguous or invalid.
        nil
      end
    end

    def normalize_arguments(args)
      return {} unless args.is_a?(Hash)

      args.transform_keys(&:to_s)
    end
  end
end
