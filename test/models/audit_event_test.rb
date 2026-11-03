require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  setup do
    @event = audit_events(:task_created_event)
  end

  test "is valid with valid attributes" do
    assert @event.valid?
  end

  test "requires event_type and valid actor_type" do
    invalid = AuditEvent.new(event_type: nil, actor_type: "hacker")
    assert_not invalid.valid?
    assert_includes invalid.errors[:event_type], "can't be blank"
    assert_includes invalid.errors[:actor_type], "is not included in the list"
  end

  test "automatically sets occurred_at on create if not provided" do
    new_event = AuditEvent.create!(
      event_type: "agent_initialized",
      actor_type: "system",
      metadata: { reason: "boot" }
    )
    assert_not_nil new_event.occurred_at
  end

  test "enforces append-only immutability: updates raise ReadOnlyRecord" do
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      @event.update(event_type: "tampered_event")
    end
  end

  test "enforces append-only immutability: deletes raise ReadOnlyRecord" do
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      @event.destroy
    end
  end

  test "associations: belongs to optional user, execution, step, and approval" do
    assert_respond_to @event, :user
    assert_respond_to @event, :execution
    assert_respond_to @event, :agent_step
    assert_respond_to @event, :approval
  end
end
