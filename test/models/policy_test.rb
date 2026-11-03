require "test_helper"

class PolicyTest < ActiveSupport::TestCase
  setup do
    @system_policy = policies(:system_allow_lookup)
    @user_policy = policies(:user_policy)
  end

  test "is valid with valid attributes" do
    assert @system_policy.valid?
    assert @user_policy.valid?
  end

  test "requires name, action_key, priority, and valid effect" do
    invalid = Policy.new(name: nil, action_key: nil, priority: nil, effect: "ignore")
    assert_not invalid.valid?
    assert_includes invalid.errors[:name], "can't be blank"
    assert_includes invalid.errors[:action_key], "can't be blank"
    assert_includes invalid.errors[:priority], "can't be blank"
    assert_includes invalid.errors[:effect], "is not included in the list"
  end

  test "supports allow, deny, and require_approval effects" do
    %w[allow deny require_approval].each do |valid_effect|
      @system_policy.effect = valid_effect
      assert @system_policy.valid?, "#{valid_effect} should be a valid effect"
    end
  end

  test "distinguishes between system-wide and user-defined policies" do
    assert @system_policy.system_wide?
    assert_not @user_policy.system_wide?
    assert_includes Policy.system_wide, @system_policy
    assert_not_includes Policy.system_wide, @user_policy
    assert_includes Policy.user_defined, @user_policy
  end

  test "orders by priority ascending" do
    sorted = Policy.by_priority
    assert sorted.first.priority <= sorted.last.priority
  end
end
