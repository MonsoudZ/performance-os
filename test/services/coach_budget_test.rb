require "test_helper"

class CoachBudgetTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @decision = @user.coaching_decisions.create!(
      decision_type: "daily_training", rule_key: "daily_training_orchestrator.v1", rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "status" => "push", "headline" => "Run the plan" },
      confidence: "high"
    )
  end

  test "a fresh day has the whole budget" do
    budget = CoachBudget.new(@user)

    assert_equal CoachBudget::DAILY_LIMIT, budget.limit
    assert_equal 0, budget.spent
    assert_equal CoachBudget::DAILY_LIMIT, budget.remaining
    assert_not budget.exhausted?
  end

  test "pending and answered questions both spend the budget" do
    ask(status: "pending")
    ask(status: "complete")

    assert_equal 2, CoachBudget.new(@user).spent
  end

  # A failure means the call raised rather than billed, and the user got no
  # answer, so the slot comes back.
  test "a failed question is refunded" do
    narrative = ask(status: "pending")
    assert_equal 1, CoachBudget.new(@user).spent

    narrative.update!(status: "failed")
    assert_equal 0, CoachBudget.new(@user).spent
  end

  test "questions asked on another local day do not count" do
    ask(at: @user.local_day_range(@user.local_date - 1).begin)
    ask(at: @user.local_day_range(@user.local_date + 1).begin)

    assert_equal 0, CoachBudget.new(@user).spent
  end

  test "another user's questions do not count" do
    other = users(:two)
    other.coach_narratives.create!(question: "Why?", status: "pending")

    assert_equal 0, CoachBudget.new(@user).spent
  end

  test "the window is the user's local day, not UTC's" do
    denver = @user.local_date
    budget = CoachBudget.new(@user, on: denver)

    assert_equal ActiveSupport::TimeZone["America/Denver"].local(denver.year, denver.month, denver.day) + 1.day,
      budget.resets_at
    assert_equal 0, budget.resets_at.in_time_zone("America/Denver").hour
  end

  test "running low starts at the low-water mark and stops at the wall" do
    (CoachBudget::DAILY_LIMIT - CoachBudget::LOW_WATER - 1).times { ask }
    assert_not CoachBudget.new(@user).running_low?

    ask
    assert CoachBudget.new(@user).running_low?

    CoachBudget::LOW_WATER.times { ask }
    budget = CoachBudget.new(@user)
    assert budget.exhausted?
    assert_not budget.running_low?
  end

  test "claim creates while there is room and refuses once there is not" do
    CoachBudget::DAILY_LIMIT.times { ask }

    assert_no_difference "CoachNarrative.count" do
      assert_nil CoachBudget.new(@user).claim { ask }
    end
  end

  test "claim yields and returns what the block built" do
    narrative = CoachBudget.new(@user).claim { ask }

    assert narrative.persisted?
    assert_equal 1, CoachBudget.new(@user).spent
  end

  # Remaining never reads negative, so the copy never offers "-3 questions left".
  test "remaining floors at zero once the limit is passed" do
    (CoachBudget::DAILY_LIMIT + 3).times { ask }

    assert_equal 0, CoachBudget.new(@user).remaining
    assert CoachBudget.new(@user).exhausted?
  end

  private

  def ask(status: "pending", at: nil)
    narrative = @user.coach_narratives.create!(
      question: "Why this plan?", coaching_decision: @decision, status: status
    )
    narrative.update_column(:created_at, at) if at
    narrative
  end
end
