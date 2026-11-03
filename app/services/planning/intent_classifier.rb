module Planning
  class IntentClassifier
    CONVERSATIONAL_PATTERNS = [
      /\A\s*(?:who|what|where|when|why|how)\s+(?:are|is|do|does|can|will|should|would)\b/i,
      /\A\s*(?:hi|hello|hey|greetings|howdy|sup|good\s+(?:morning|afternoon|evening))\b/i,
      /\b(?:who\s+are\s+you|what\s+is\s+your\s+name|what\s+can\s+you\s+do|how\s+do\s+you\s+work|explain\s+how\s+you\s+work|introduce\s+yourself)\b/i,
      /\A\s*(?:explain|describe|tell\s+me\s+about|brainstorm|discuss|clarify|define|summarize)\b/i,
      /\A\s*(?:can\s+you|could\s+you|please)\s+(?:explain|describe|help|brainstorm|discuss|clarify|tell)\b/i,
      /\b(?:brainstorm|brainstorming|concept|difference\s+between|tutorial|guide|architecture|philosophy|thoughts\s+on)\b/i,
      /\b(?:help|documentation|about\s+you)\b/i,
      /\?\s*\z/
    ].freeze

    ACTIONABLE_PATTERNS = [
      /\b(?:verify|validate|lookup|retrieve|fetch|check|inspect|audit)\s+(?:invoice|bill|record|account|voucher|po|contract)\b/i,
      /\b(?:prepare|create|generate|issue|initiate|process|make|send|disburse|pay)\s+(?:payment|transfer|payout|disbursement|voucher|refund)\b/i,
      /\b(?:generate|create)\s+(?:audit|report|compliance|summary)\b/i,
      /\b(?:INV-\d+|PO-\d+|TX-\d+|PO[0-9]+|TX[0-9]+)\b/i,
      /\b(?:inr|usd|eur|gbp|₹|\$)\s*[0-9,]+/i,
      /\b[0-9,]+\s*(?:inr|usd|eur|rupees|dollars|cents)\b/i
    ].freeze

    def self.classify(instruction)
      new(instruction).classify
    end

    def self.conversational?(instruction)
      classify(instruction) == "conversation"
    end

    def self.actionable?(instruction)
      classify(instruction) == "action_plan"
    end

    def initialize(instruction)
      @instruction = instruction.to_s.strip
    end

    def classify
      return "conversation" if @instruction.blank?

      # 1. Actionable score (presence of concrete entities like invoice IDs, currencies, tool verbs)
      actionable_score = 0
      ACTIONABLE_PATTERNS.each do |pattern|
        actionable_score += 2 if @instruction =~ pattern
      end

      # 2. Conversational score (questions, greetings, conceptual inquiries)
      conversational_score = 0
      CONVERSATIONAL_PATTERNS.each do |pattern|
        conversational_score += 2 if @instruction =~ pattern
      end

      # Explicit actionable entity dominates (e.g. "Verify invoice INV-100" or "Prepare payment of INR 5000")
      return "action_plan" if actionable_score > conversational_score && actionable_score >= 2

      # General question or greeting
      return "conversation" if conversational_score > 0

      # Imperative verb check (e.g. "Lookup invoice", "Prepare payment")
      imperative_action_command? ? "action_plan" : "conversation"
    end

    def conversation?
      classify == "conversation"
    end

    def action_plan?
      classify == "action_plan"
    end

    private

    def imperative_action_command?
      first_word = @instruction.split.first.to_s.downcase
      %w[verify prepare lookup retrieve fetch check inspect audit pay transfer issue disburse process generate create].include?(first_word)
    end
  end
end
