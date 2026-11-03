module Planning
  class PlanNormalizer
    def self.normalize(plan_data)
      new.normalize(plan_data)
    end

    def normalize(plan_data)
      goal = (plan_data["goal"] || plan_data[:goal]).to_s.strip
      summary = (plan_data["summary"] || plan_data[:summary]).to_s.strip
      raw_steps = plan_data["steps"] || plan_data[:steps] || []

      normalized_steps = raw_steps.map do |step|
        {
          "step_number" => (step["step_number"] || step[:step_number]).to_i,
          "action" => (step["action"] || step[:action]).to_s.strip,
          "arguments" => normalize_arguments(step["arguments"] || step[:arguments]),
          "description" => (step["description"] || step[:description]).to_s.strip
        }
      end

      {
        "goal" => goal,
        "summary" => summary,
        "steps" => normalized_steps
      }
    end

    private

    def normalize_arguments(args)
      return {} unless args.is_a?(Hash)

      args.transform_keys(&:to_s)
    end
  end
end
