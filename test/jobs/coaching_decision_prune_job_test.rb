require "test_helper"

class CoachingDecisionPruneJobTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "does nothing when no retention window is configured" do
    old = create_decision(created_at: 2.years.ago)

    assert_no_difference "CoachingDecision.count" do
      CoachingDecisionPruneJob.perform_now(nil)
    end
    assert CoachingDecision.exists?(old.id)
  end

  test "removes only unreferenced decisions older than the window" do
    old_root = create_decision(created_at: 400.days.ago)
    recent = create_decision(created_at: 10.days.ago)
    old_child = create_decision(created_at: 400.days.ago, decision_type: "daily_readiness")
    recent_parent = create_decision(created_at: 5.days.ago)
    recent_parent.child_links.create!(child_decision: old_child, role: "readiness")

    CoachingDecisionPruneJob.perform_now(365)

    assert_not CoachingDecision.exists?(old_root.id), "unreferenced old decision should be pruned"
    assert CoachingDecision.exists?(recent.id), "recent decision should be kept"
    assert CoachingDecision.exists?(old_child.id), "decision referenced as a child must be kept"
    assert CoachingDecision.exists?(recent_parent.id), "recent parent should be kept"
  end

  private

  def create_decision(decision_type: "daily_training", created_at: Time.current)
    @user.coaching_decisions.create!(
      decision_type: decision_type,
      rule_key: "test.v1",
      rule_version: "1.0.0",
      inputs: {},
      output: {},
      citations: [],
      confidence: "low",
      created_at: created_at
    )
  end
end
