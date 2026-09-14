require "test_helper"

# Two questions asked at the same instant, with one slot left.
#
# Counting and inserting are two statements, so without a lock both requests
# read the same count and both insert — the cap is quietly oversold, and the
# overshoot grows with concurrency. This runs outside a transaction because the
# threads need their own connections to see each other's rows at all.
class CoachBudgetRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # Long enough that the count-and-insert window is wide open. Without the lock
  # the second thread reads the count while the first is still inside; with it,
  # the second waits and then finds a full day.
  HOLD = 0.3

  setup do
    @user = User.create!(
      email_address: "coach-budget-race@example.com", password: "password", time_zone: "America/Denver"
    )
    @decision = @user.coaching_decisions.create!(
      decision_type: "daily_training", rule_key: "daily_training_orchestrator.v1", rule_version: "1.0.0",
      inputs: { "plan_date" => @user.local_date.iso8601 },
      output: { "status" => "push", "headline" => "Run the plan" },
      confidence: "high"
    )
    (CoachBudget::DAILY_LIMIT - 1).times { ask }
  end

  teardown do
    @user.coach_narratives.delete_all
    @user.coaching_decisions.delete_all
    User.where(id: @user.id).delete_all
  end

  test "two questions asked at once cannot both take the last slot" do
    granted = Queue.new

    threads = 2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user = User.find(@user.id)
          claimed = CoachBudget.new(user).claim do
            sleep HOLD
            user.coach_narratives.create!(
              question: "Race #{i}", coaching_decision: @decision, status: "pending"
            )
          end
          granted << !claimed.nil?
        end
      end
    end
    threads.each(&:join)

    assert_equal 1, Array.new(granted.size) { granted.pop }.count(true),
      "both requests were sold the last slot"
    assert_equal CoachBudget::DAILY_LIMIT, @user.coach_narratives.reload.count
  end

  private

  def ask
    @user.coach_narratives.create!(question: "Why?", coaching_decision: @decision, status: "pending")
  end
end
