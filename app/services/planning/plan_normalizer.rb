module Planning
  class PlanNormalizer
    def self.normalize(plan_data)
      new.normalize(plan_data)
    end

    def normalize(plan_data)
      raw_mode = (plan_data["mode"] || plan_data[:mode]).to_s.strip
      raw_steps = plan_data["steps"] || plan_data[:steps] || []

      mode = if raw_mode.present?
        raw_mode
      elsif raw_steps.any?
        "action_plan"
      else
        "conversation"
      end

      response_text = (plan_data["response"] || plan_data[:response]).to_s.strip
      summary = (plan_data["summary"] || plan_data[:summary]).to_s.strip.presence || response_text

      if mode == "conversation"
        requires_action = false
        goal = (plan_data["goal"] || plan_data[:goal]).presence
        normalized_steps = []
      else
        requires_action = true
        goal = (plan_data["goal"] || plan_data[:goal]).to_s.strip
        normalized_steps = raw_steps.map do |step|
          {
            "step_number" => (step["step_number"] || step[:step_number]).to_i,
            "action" => (step["action"] || step[:action]).to_s.strip,
            "arguments" => normalize_arguments(step["arguments"] || step[:arguments]),
            "description" => (step["description"] || step[:description]).to_s.strip
          }
        end
      end

      result = {
        "mode" => mode,
        "response" => response_text,
        "requires_action" => requires_action,
        "goal" => goal,
        "summary" => summary,
        "steps" => normalized_steps
      }

      if (clarification = (plan_data["clarification_needed"] || plan_data[:clarification_needed]).to_s.strip).present?
        result["clarification_needed"] = clarification
      end

      if (explanation = (plan_data["explanation"] || plan_data[:explanation]).to_s.strip).present?
        result["explanation"] = explanation
      end

      result
    end

    private

    def normalize_arguments(args)
      return {} unless args.is_a?(Hash)

      args.transform_keys(&:to_s)
    end
  end
end
