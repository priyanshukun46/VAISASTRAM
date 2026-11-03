require "test_helper"

class IntentClassifierTest < ActiveSupport::TestCase
  # =========================================================
  # Scenarios 1 - 5: Intent Classification Tests
  # =========================================================

  test "Scenario 1: 'Who are you?' classifies as conversation" do
    assert_equal "conversation", Planning::IntentClassifier.classify("Who are you?")
    assert Planning::IntentClassifier.conversational?("Who are you?")
    refute Planning::IntentClassifier.actionable?("Who are you?")
  end

  test "Scenario 2: 'Hello' classifies as conversation" do
    assert_equal "conversation", Planning::IntentClassifier.classify("Hello")
    assert Planning::IntentClassifier.conversational?("Hello")
  end

  test "Scenario 3: 'Explain how you work' classifies as conversation" do
    assert_equal "conversation", Planning::IntentClassifier.classify("Explain how you work")
    assert Planning::IntentClassifier.conversational?("Explain how you work")
  end

  test "Scenario 4: 'Verify invoice INV-100' classifies as action_plan" do
    assert_equal "action_plan", Planning::IntentClassifier.classify("Verify invoice INV-100")
    assert Planning::IntentClassifier.actionable?("Verify invoice INV-100")
  end

  test "Scenario 5: 'Prepare payment of INR 5000' classifies as action_plan" do
    assert_equal "action_plan", Planning::IntentClassifier.classify("Prepare payment of INR 5000")
    assert Planning::IntentClassifier.actionable?("Prepare payment of INR 5000")
  end

  test "classifies additional conversational greetings and questions" do
    conversations = [
      "Hi there",
      "Good morning",
      "What is VAISASTRAM?",
      "Can you explain your policy architecture?",
      "Tell me about yourself",
      "Help me understand how you work",
      "Why are tools not executed during planning?"
    ]

    conversations.each do |text|
      assert_equal "conversation", Planning::IntentClassifier.classify(text), "Expected '#{text}' to classify as conversation"
    end
  end

  test "classifies general-purpose technical, scientific, brainstorming, and conceptual inquiries as conversation" do
    general_topics = [
      "Explain how quantum computing works",
      "How does the Raft consensus algorithm work?",
      "Brainstorm architecture ideas for an event-driven system",
      "What is Ruby on Rails?",
      "Discuss microservices vs monoliths",
      "Define idempotent operations in HTTP REST APIs",
      "Tell me about distributed transactions across databases",
      "Can you explain how neural networks learn?",
      "Please describe the difference between concurrency and parallelism"
    ]

    general_topics.each do |text|
      assert_equal "conversation", Planning::IntentClassifier.classify(text), "Expected '#{text}' to classify as conversation"
      assert Planning::IntentClassifier.conversational?(text)
      refute Planning::IntentClassifier.actionable?(text)
    end
  end

  test "classifies additional actionable task instructions" do
    actions = [
      "Lookup invoice INV-99",
      "Retrieve invoice details for client ACME",
      "Process refund for transaction TX-88",
      "Generate monthly compliance audit report",
      "Disburse payment of 1000 USD to vendor"
    ]

    actions.each do |text|
      assert_equal "action_plan", Planning::IntentClassifier.classify(text), "Expected '#{text}' to classify as action_plan"
    end
  end

  test "defaults blank instruction to conversation" do
    assert_equal "conversation", Planning::IntentClassifier.classify("")
    assert_equal "conversation", Planning::IntentClassifier.classify(nil)
    assert_equal "conversation", Planning::IntentClassifier.classify("   ")
  end
end
