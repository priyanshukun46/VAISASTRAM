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

      # Determine and validate response mode
      raw_mode = plan_data["mode"] || plan_data[:mode]
      steps = plan_data["steps"] || plan_data[:steps]

      if raw_mode.nil?
        # Backward compatibility with earlier unit tests that omitted mode
        mode = if plan_data["clarification_needed"].present? || plan_data["explanation"].present? || plan_data["requires_action"] == false
          "conversation"
        elsif (plan_data["goal"] || plan_data[:goal]).present?
          "action_plan"
        elsif steps.is_a?(Array) && steps.empty?
          "conversation"
        else
          raise ValidationError, "Missing required field 'mode' in plan"
        end
      else
        mode = raw_mode.to_s.strip
        unless PlanSchema::MODES.include?(mode)
          raise ValidationError, "Invalid mode '#{mode}'. Allowed modes are: #{PlanSchema::MODES.join(', ')}"
        end
      end

      # Check required response field
      unless plan_data.key?("response") || plan_data.key?(:response)
        raise ValidationError, "Missing required field 'response' in plan"
      end

      response_text = (plan_data["response"] || plan_data[:response]).to_s.strip
      raise ValidationError, "Response cannot be empty" if response_text.empty?

      # Anti-hallucination: Never imply an action has already been executed
      FORBIDDEN_COMPLETION_PATTERNS.each do |pattern|
        if response_text =~ pattern
          raise ValidationError, "AI response falsely implies actions have already been executed: '#{response_text}'"
        end
      end

      # Check required steps field
      unless plan_data.key?("steps") || plan_data.key?(:steps)
        raise ValidationError, "Missing required field 'steps' in plan"
      end

      # Steps must always be an array
      unless steps.is_a?(Array)
        raise ValidationError, "Field 'steps' must be an Array, got #{steps.class.name}"
      end

      # =========================================================
      # 1. Conversation Mode Validation
      # =========================================================
      if mode == "conversation"
        unless steps.empty?
          raise ValidationError, "Conversation mode must not contain action steps, got #{steps.size} steps"
        end

        if plan_data.key?("summary") || plan_data.key?(:summary)
          summary = (plan_data["summary"] || plan_data[:summary]).to_s.strip
          raise ValidationError, "Summary cannot be empty if provided" if summary.empty?
        end

        # Conversation mode does not invoke the action-plan validator
        return true
      end

      # =========================================================
      # 2. Action Plan Mode Validation
      # =========================================================
      if mode == "action_plan"
        unless plan_data.key?("goal") || plan_data.key?(:goal)
          raise ValidationError, "Missing required field 'goal' in plan"
        end

        goal = (plan_data["goal"] || plan_data[:goal]).to_s.strip
        raise ValidationError, "Goal cannot be empty in plan" if goal.empty?

        if steps.empty?
          raise ValidationError, "Plan must contain at least one step"
        end

        if steps.size > PlanSchema::MAX_STEPS
          raise ValidationError, "Plan exceeds maximum allowed steps (#{steps.size} > #{PlanSchema::MAX_STEPS})"
        end

        if plan_data.key?("summary") || plan_data.key?(:summary)
          summary = (plan_data["summary"] || plan_data[:summary]).to_s.strip
          raise ValidationError, "Summary cannot be empty if provided" if summary.empty?
        end

        # Step-by-step verification
        expected_step_number = 1
        allowed_keys = PlanSchema::ALLOWED_STEP_KEYS

        steps.each_with_index do |step, idx|
          unless step.is_a?(Hash)
            raise ValidationError, "Step ##{idx + 1} must be an object, got #{step.class.name}"
          end

          unexpected_step_keys = step.keys.map(&:to_s) - allowed_keys
          if unexpected_step_keys.any?
            raise ValidationError, "Step ##{idx + 1} contains unexpected fields: #{unexpected_step_keys.join(', ')}"
          end

          allowed_keys.each do |k|
            unless step.key?(k) || step.key?(k.to_sym)
              raise ValidationError, "Step ##{idx + 1} is missing required field '#{k}'"
            end
          end

          step_num = step["step_number"] || step[:step_number]
          unless step_num.is_a?(Integer) && step_num == expected_step_number
            raise ValidationError, "Step number mismatch: expected #{expected_step_number}, got #{step_num.inspect}"
          end

          action = (step["action"] || step[:action]).to_s.strip
          raise ValidationError, "Step ##{step_num} action cannot be blank" if action.empty?

          unless action =~ /\A[a-z0-9_]+\z/
            raise ValidationError, "Step ##{step_num} action '#{action}' has invalid format; only lowercase alphanumeric and underscores allowed"
          end

          if allowed_tools.present? && !allowed_tools.include?(action)
            raise ValidationError, "Step ##{step_num} proposes unknown or disallowed action '#{action}'. Allowed tools: #{allowed_tools.join(', ')}"
          end

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

          desc = (step["description"] || step[:description]).to_s.strip
          raise ValidationError, "Step ##{step_num} description cannot be blank" if desc.empty?

          expected_step_number += 1
        end

        return true
      end
    end
  end
end
