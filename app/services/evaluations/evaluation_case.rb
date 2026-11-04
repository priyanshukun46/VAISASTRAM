module Evaluations
  class EvaluationCase
    attr_reader :id, :name, :category, :description, :block

    def initialize(id:, name:, category:, description:, &block)
      @id = id
      @name = name
      @category = category.to_s.downcase.to_sym
      @description = description
      @block = block
    end

    def run
      @block.call
    end
  end
end
