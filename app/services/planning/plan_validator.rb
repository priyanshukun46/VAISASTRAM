module Planning
  class ValidationError < StandardError; end

  class PlanValidator
    FORBIDDEN_COMPLETION_PATTERNS = [
      /\b(?:i have|we have|agent has)\s+(?:executed|performed|completed|paid|disbursed|sent|transferred|deleted)\b/i,
      /\b(?:payment|transaction|transfer)\s+(?:was|has been|is)\s+(?:completed|sent|transferred|executed)\b/i,
      /\baction(?:s)?\s+(?:have been|were|was)\s+executed\b/i
    ].freeze

    def self.validate!(plan_data, allowed_tools: [])
      new.validate!(plan_data, allowed_tools: allowed_tools)
    end

    def validate!(plan_data, allowed_tools: [])
      unless plan_data.is_a?(Hash)
        raise ValidationError, "Plan root must be a JSON object, got #{plan_data.class.name}"
      end

      # Reject unexpected top-level keys
      unexpected_keys = plan_data.keys.map(&:to_s) - PlanSchema::ALLOWED_TOP_LEVEL_KEYS
      if unexpected_keys.any?
        raise ValidationError, "Unexpected top-level fields in plan: #{unexpected_keys.join(', ')}"
      end

      # Check required baseline fields (Task 2 unified contract)
      %w[goal response steps].each do |key|
        unless plan_data.key?(key) || plan_data.key?(key.to_sym)
          raise ValidationError, "Missing required field '#{key}' in plan"
        end
      end

      # Type checks for goal & response
      goal = (plan_data["goal"] || plan_data[:goal]).to_s.strip
      response_text = (plan_data["response"] || plan_data[:response]).to_s.strip

      raise ValidationError, "Goal cannot be empty" if goal.empty?
      raise ValidationError, "Response cannot be empty" if response_text.empty?

      # Optional summary check if provided
      if plan_data.key?("summary") || plan_data.key?(:summary)
        summary = (plan_data["summary"] || plan_data[:summary]).to_s.strip
        raise ValidationError, "Summary cannot be empty if provided" if summary.empty?
      end

      # Anti-hallucination: Never imply an action has already been executed
      FORBIDDEN_COMPLETION_PATTERNS.each do |pattern|
        if response_text =~ pattern
          raise ValidationError, "AI response falsely implies actions have already been executed: '#{response_text}'"
        end
      end

      # Steps array checks
      steps = plan_data["steps"] || plan_data[:steps]
      unless steps.is_a?(Array)
        raise ValidationError, "Field 'steps' must be an Array, got #{steps.class.name}"
      end

      # Determine if action steps are required
      requires_action = if plan_data.key?("requires_action")
        ActiveModel::Type::Boolean.new.cast(plan_data["requires_action"])
      elsif plan_data.key?(:requires_action)
        ActiveModel::Type::Boolean.new.cast(plan_data[:requires_action])
      else
        true # Default to true for backward compatibility when not explicitly false
      end

      if requires_action && steps.empty?
        raise ValidationError, "Plan must contain at least one step"
      end

      if steps.size > PlanSchema::MAX_STEPS
        raise ValidationError, "Plan exceeds maximum allowed steps (#{steps.size} > #{PlanSchema::MAX_STEPS})"
      end

      # Step-by-step verification
      expected_step_number = 1
      allowed_keys = PlanSchema::ALLOWED_STEP_KEYS

      steps.each_with_index do |step, idx|
        unless step.is_a?(Hash)
          raise ValidationError, "Step ##{idx + 1} must be an object, got #{step.class.name}"
        end

        # Check unexpected step keys
        unexpected_step_keys = step.keys.map(&:to_s) - allowed_keys
        if unexpected_step_keys.any?
          raise ValidationError, "Step ##{idx + 1} contains unexpected fields: #{unexpected_step_keys.join(', ')}"
        end

        # Required fields in step
        allowed_keys.each do |k|
          unless step.key?(k) || step.key?(k.to_sym)
            raise ValidationError, "Step ##{idx + 1} is missing required field '#{k}'"
          end
        end

        # Step number validation (must be 1-based sequential integer)
        step_num = step["step_number"] || step[:step_number]
        unless step_num.is_a?(Integer) && step_num == expected_step_number
          raise ValidationError, "Step number mismatch: expected #{expected_step_number}, got #{step_num.inspect}"
        end

        # Action validation
        action = (step["action"] || step[:action]).to_s.strip
        if action.empty?
          raise ValidationError, "Step ##{step_num} action cannot be blank"
        end

        unless action =~ /\A[a-z0-9_]+\z/
          raise ValidationError, "Step ##{step_num} action '#{action}' has invalid format; only lowercase alphanumeric and underscores allowed"
        end

        if allowed_tools.present? && !allowed_tools.include?(action)
          raise ValidationError, "Step ##{step_num} proposes unknown or disallowed action '#{action}'. Allowed tools: #{allowed_tools.join(', ')}"
        end

        # Arguments validation
        arguments = step["arguments"] || step[:arguments]
        unless arguments.is_a?(Hash)
          raise ValidationError, "Step ##{step_num} arguments must be a JSON object, got #{arguments.class.name}"
        end

        arguments.each_key do |k|
          k_str = k.to_s
          if k_str.start_with?("__") || k_str =~ /\A(eval|exec|system|`|shell)\z/i
            raise ValidationError, "Step ##{step_num}: Malicious argument key detected '#{k_str}'"
          end
        end

        # Description validation
        desc = (step["description"] || step[:description]).to_s.strip
        if desc.empty?
          raise ValidationError, "Step ##{step_num} description cannot be blank"
        end

        expected_step_number += 1
      end

      true
    end
  end
end
