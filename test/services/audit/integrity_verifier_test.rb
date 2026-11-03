require "test_helper"

class IntegrityVerifierTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @task = tasks(:invoice_task)
    @execution = executions(:invoice_execution)
    @chain_id = "test_chain_#{SecureRandom.hex(6)}"
  end

  test "Test 11: Correct hash generation, previous hash linking, and valid chain verification" do
    e1 = Audit::Recorder.record!(
      event_type: "task_created",
      actor_type: "user",
      actor_id: @user.id,
      user: @user,
      task: @task,
      execution: @execution,
      metadata: { note: "First event" }
    )

    e2 = Audit::Recorder.record!(
      event_type: "plan_generated",
      actor_type: "agent",
      actor_id: "VAISASTRAM Agent",
      user: @user,
      task: @task,
      execution: @execution,
      metadata: { steps: 2 }
    )

    e3 = Audit::Recorder.record!(
      event_type: "policy_evaluated",
      actor_type: "policy_engine",
      actor_id: "payment_limit_rule",
      user: @user,
      task: @task,
      execution: @execution,
      policy_decision: "require_approval"
    )

    chain_id = "execution:#{@execution.id}"
    result = Audit::IntegrityVerifier.verify_chain(chain_id)

    assert result.valid?, "Expected chain to be valid, but got errors: #{result.errors.join(', ')}"
    assert_equal 3, result.verified_count
    assert_empty result.tampered_event_ids
    assert_empty result.broken_link_event_ids
    assert_empty result.missing_sequences

    assert_equal Audit::EventBuilder::GENESIS_HASH, e1.prev_event_hash
    assert_equal e1.event_hash, e2.prev_event_hash
    assert_equal e2.event_hash, e3.prev_event_hash
  end

  test "Test 12: Tampered metadata or event attributes are detected" do
    e1 = Audit::Recorder.record!(
      event_type: "task_created",
      actor_type: "user",
      actor_id: @user.id,
      user: @user,
      task: @task,
      execution: @execution,
      metadata: { amount: 5000 }
    )

    chain_id = "execution:#{@execution.id}"

    # Tamper with event in database directly (bypassing model callbacks)
    AuditEvent.where(id: e1.id).update_all(metadata: { amount: 99999 }.to_json)

    result = Audit::IntegrityVerifier.verify_chain(chain_id)

    assert_not result.valid?
    assert_includes result.tampered_event_ids, e1.id
    assert result.errors.any? { |err| err.include?("does not match recomputed hash") }
  end

  test "Test 13: Broken previous hash link is detected" do
    e1 = Audit::Recorder.record!(
      event_type: "task_created",
      actor_type: "user",
      actor_id: @user.id,
      task: @task,
      execution: @execution
    )

    e2 = Audit::Recorder.record!(
      event_type: "plan_generated",
      actor_type: "agent",
      actor_id: "agent",
      task: @task,
      execution: @execution
    )

    chain_id = "execution:#{@execution.id}"

    # Break previous hash link on second event
    AuditEvent.where(id: e2.id).update_all(prev_event_hash: "CORRUPTED_HASH_VALUE")

    result = Audit::IntegrityVerifier.verify_chain(chain_id)

    assert_not result.valid?
    assert_includes result.broken_link_event_ids, e2.id
  end

  test "Test 14: Missing event or sequence gap is detected" do
    e1 = Audit::Recorder.record!(
      event_type: "task_created",
      actor_type: "user",
      actor_id: @user.id,
      task: @task,
      execution: @execution
    )

    e2 = Audit::Recorder.record!(
      event_type: "plan_generated",
      actor_type: "agent",
      actor_id: "agent",
      task: @task,
      execution: @execution
    )

    e3 = Audit::Recorder.record!(
      event_type: "tool_requested",
      actor_type: "system",
      actor_id: "executor",
      task: @task,
      execution: @execution
    )

    chain_id = "execution:#{@execution.id}"

    # Simulate deletion of middle event e2 via direct SQL
    ActiveRecord::Base.connection.execute("DELETE FROM audit_events WHERE id = #{e2.id}")

    result = Audit::IntegrityVerifier.verify_chain(chain_id)

    assert_not result.valid?
    # Sequence discontinuity (jump from 1 to 3) and broken hash link
    assert_includes result.missing_sequences, 2
    assert_includes result.broken_link_event_ids, e3.id
  end

  test "Test 15: Concurrent event creation does not corrupt the chain" do
    threads = []
    thread_count = 5

    thread_count.times do |i|
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Audit::Recorder.record!(
            event_type: "tool_validated",
            actor_type: "system",
            actor_id: "worker_#{i}",
            task: @task,
            execution: @execution,
            metadata: { thread_index: i }
          )
        end
      end
    end

    threads.each(&:join)

    chain_id = "execution:#{@execution.id}"
    result = Audit::IntegrityVerifier.verify_chain(chain_id)

    assert result.valid?, "Expected concurrent chain to remain valid: #{result.errors.join(', ')}"
    assert_equal thread_count, result.verified_count
    assert_empty result.tampered_event_ids
    assert_empty result.broken_link_event_ids
  end
end
