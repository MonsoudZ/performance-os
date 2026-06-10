require "test_helper"
require "turbo/broadcastable/test_helper"

class ReadinessRecomputeJobTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup { @user = users(:one) }

  test "runs the readiness pipeline and broadcasts a refresh to the user" do
    input = @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date,
      sleep_minutes: 450,
      sleep_quality: 4,
      soreness: 2,
      fatigue: 2,
      stress: 3,
      source: "manual"
    )

    assert_turbo_stream_broadcasts(@user, count: 1) do
      assert_difference -> { @user.readiness_scores.count }, 1 do
        assert_difference "CoachingDecision.count", 3 do
          assert_difference "CoachingDecisionLink.count", 2 do
            ReadinessRecomputeJob.perform_now(input)
          end
        end
      end
    end

    assert_equal "daily_training_orchestrator.v1", CoachingDecision.last.rule_key
  end
end
