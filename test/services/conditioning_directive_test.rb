require "test_helper"

class ConditioningDirectiveTest < ActiveSupport::TestCase
  test "marathon measures weekly km and pushes a quality session when behind and ready" do
    directive = call("marathon", "push", km: 10.0)

    assert_equal "distance", directive["metric"]
    assert_equal 40, directive["target"]
    assert_equal 10.0, directive["done"]
    assert_equal "quality", directive["focus"]
    assert_match(/long run|tempo/i, directive["headline"])
  end

  test "low readiness keeps it to Zone 2 regardless of goal" do
    directive = call("marathon", "recover", km: 5.0)

    assert_equal "recovery", directive["focus"]
    assert_match(/Zone 2/i, directive["headline"])
  end

  test "longevity measures Zone 2 minutes and holds steady once the target is met" do
    directive = call("longevity", "steady", zone2: 160)

    assert_equal "zone2", directive["metric"]
    assert_equal 150, directive["target"]
    assert_equal 160, directive["done"]
    assert_equal "maintain", directive["focus"]
  end

  test "a strength goal treats conditioning as optional recovery work" do
    directive = call("increase_strength", "steady", zone2: 10)

    assert_equal "steady", directive["focus"]
    assert_match(/Zone 2/i, directive["guidance"])
  end

  test "no goal falls back to a base Zone 2 default" do
    directive = call(nil, "steady")

    assert_equal "zone2", directive["metric"]
    assert_equal 90, directive["target"]
  end

  private

  def call(goal_type, readiness_status, sessions: 0, km: 0.0, zone2: 0)
    goal = goal_type && GoalPeriod.new(goal_type: goal_type)
    summary = Struct.new(:session_count, :total_distance_km, :zone2_minutes).new(sessions, km, zone2)
    ConditioningDirective.new(goal: goal, readiness_status: readiness_status, summary: summary).call
  end
end
