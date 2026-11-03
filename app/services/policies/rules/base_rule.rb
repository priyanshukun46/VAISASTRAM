module Policies
  module Rules
    class BaseRule
      attr_reader :rule_id, :name, :description, :priority

      def initialize(rule_id:, name:, description:, priority: 100)
        @rule_id = rule_id.to_s.freeze
        @name = name.freeze
        @description = description.freeze
        @priority = priority
      end

      # Subclasses must implement evaluate(context)
      # Returns a Policies::Decision or nil if rule does not apply
      def evaluate(context)
        raise NotImplementedError, "#{self.class.name} must implement #evaluate(context)"
      end

      def applies_to?(context)
        true
      end
    end
  end
end
