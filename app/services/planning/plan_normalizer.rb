module Planning
  class PlanNormalizer
    def self.normalize(plan_data)
      new.normalize(plan_data)
    end

    def normalize(plan_data)
      goal = (plan_data["goal"] || plan_data[:goal]).to_s.strip
      summary = (plan_data["summary"] || plan_data[:summary]).to_s.strip
      raw_steps = plan_data["steps"] || plan_data[:steps] || []

      requires_action = if plan_data.key?("requires_action")
        ActiveModel::Type::Boolean.new.cast(plan_data["requires_action"])
      elsif plan_data.key?(:requires_action)
        ActiveModel::Type::Boolean.new.cast(plan_data[:requires_action])
      else
        raw_steps.any?
      end

      response_text = (plan_data["response"] || plan_data[:response]).to_s.strip
      if response_text.empty?
        response_text = if requires_action && raw_steps.any?
          "I have proposed an execution plan with #{raw_steps.size} #{'step'.pluralize(raw_steps.size)} to #{goal.downcase}. These actions are submitted for Ruby policy evaluation before any execution."
        else
          summary.presence || "I have received your instruction."
        end
      end

      normalized_steps = raw_steps.map do |step|
        {
          "step_number" => (step["step_number"] || step[:step_number]).to_i,
          "action" => (step["action"] || step[:action]).to_s.strip,
          "arguments" => normalize_arguments(step["arguments"] || step[:arguments]),
          "description" => (step["description"] || step[:description]).to_s.strip
        }
      end

      result = {
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
