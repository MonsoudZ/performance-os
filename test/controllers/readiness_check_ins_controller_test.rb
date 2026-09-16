require "test_helper"

class ReadinessCheckInsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "creates a check-in and recommendation" do
    assert_difference "DailyReadinessInput.count", 1 do
      assert_difference "ReadinessScore.count", 1 do
        assert_difference "CoachingDecision.count", 3 do
          assert_difference "CoachingDecisionLink.count", 2 do
            # The check-in persists synchronously; the evaluator pipeline runs in
            # ReadinessRecomputeJob, so drive it inline to assert its effects.
            perform_enqueued_jobs do
              post readiness_check_in_path, params: {
                daily_readiness_input: {
                  sleep_hours: 7.5,
                  sleep_quality: 4,
                  soreness: 2,
                  fatigue: 2,
                  stress: 3
                }
              }
            end
          end
        end
      end
    end

    assert_redirected_to root_path
    assert_equal "daily_training_orchestrator.v1", CoachingDecision.last.rule_key
  end

  test "enqueues the recompute job without computing inline" do
    assert_enqueued_with(job: ReadinessRecomputeJob) do
      assert_no_difference "CoachingDecision.count" do
        post readiness_check_in_path, params: {
          daily_readiness_input: {
            sleep_hours: 7.5, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3
          }
        }
      end
    end
  end

  # Answering the check-in must not throw away where the night's figure came
  # from: the row still holds the watch's measurement, so it is still mixed
  # evidence, and the dashboard goes on saying so.
  test "checking in on a watch-synced night keeps the sleep figure attributed" do
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date, sleep_minutes: 447, source: "healthkit"
    )

    post readiness_check_in_path, params: {
      daily_readiness_input: { sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
    }

    input = @user.daily_readiness_inputs.sole
    assert_equal "mixed", input.source
    assert input.sleep_from_watch?, "the watch still measured this night"
  end

  test "a check-in with nothing measured behind it is plainly manual" do
    post readiness_check_in_path, params: {
      daily_readiness_input: { sleep_hours: 7.5, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
    }

    input = @user.daily_readiness_inputs.sole
    assert_equal "manual", input.source
    assert_not input.sleep_from_watch?, "typing the hours in is not the watch measuring them"
  end

  test "uses the signed-in user's local calendar day" do
    @user.update!(time_zone: "America/Denver")

    travel_to Time.utc(2026, 6, 10, 5, 30) do
      post readiness_check_in_path, params: {
        daily_readiness_input: {
          sleep_hours: 7.5,
          sleep_quality: 4,
          soreness: 2,
          fatigue: 2,
          stress: 3
        }
      }
    end

    assert_equal Date.new(2026, 6, 9), @user.daily_readiness_inputs.last.metric_date
  end
end
