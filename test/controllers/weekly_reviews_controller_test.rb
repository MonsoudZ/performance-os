require "test_helper"

class WeeklyReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @user.goal_periods.create!(
      goal_type: "build_muscle",
      params: { "target_kcal" => 2_800, "target_protein_g" => 180 },
      started_on: Date.current
    )
  end

  test "shows the weekly review workspace" do
    get weekly_review_path

    assert_response :success
    assert_select "h1", "Is the plan working?"
  end

  test "creates a review and its nutrition adjustment decision" do
    assert_difference "CoachingDecision.count", 2 do
      # The review + adjustment are produced by WeeklyReviewRecomputeJob.
      perform_enqueued_jobs do
        post weekly_review_path
      end
    end

    assert_redirected_to weekly_review_path
    assert_equal "weekly_review", CoachingDecision.order(:created_at).second_to_last.decision_type
    assert_equal "nutrition_adjustment", CoachingDecision.order(:created_at).last.decision_type
  end

  test "enqueues the review job and returns immediately" do
    assert_enqueued_with(job: WeeklyReviewRecomputeJob) do
      assert_no_difference "CoachingDecision.count" do
        post weekly_review_path
      end
    end
    assert_redirected_to weekly_review_path
  end
end
