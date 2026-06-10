require "test_helper"

class GoalPeriodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "shows the goal workspace" do
    get goal_periods_path

    assert_response :success
    assert_select "h1", "Training goal."
  end

  test "creates a goal and enqueues a nutrition recompute" do
    assert_difference "GoalPeriod.count", 1 do
      assert_enqueued_with(job: NutritionRecomputeJob) do
        post goal_periods_path, params: {
          goal_period: { goal_type: "lose_fat", started_on: Date.current, target_kcal: "2100" }
        }
      end
    end

    goal = @user.goal_periods.order(:id).last
    assert_equal "lose_fat", goal.goal_type
    assert_equal 2100, goal.params["target_kcal"]
    assert_redirected_to goal_periods_path
  end

  test "switching goals retires the previously active one" do
    old = @user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current - 30.days)

    post goal_periods_path, params: {
      goal_period: { goal_type: "increase_strength", started_on: Date.current }
    }

    assert_equal Date.current - 1.day, old.reload.ended_on
    assert_equal "increase_strength", @user.active_goal.goal_type
    # The partial unique index allows exactly one open goal.
    assert_equal 1, @user.goal_periods.active.count
  end

  test "rejects an unknown goal type" do
    assert_no_difference "GoalPeriod.count" do
      post goal_periods_path, params: {
        goal_period: { goal_type: "get_swole", started_on: Date.current }
      }
    end

    assert_response :unprocessable_entity
  end

  test "ends the active goal" do
    goal = @user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current - 10.days)

    patch finish_goal_period_path(goal)

    assert_equal Date.current - 1.day, goal.reload.ended_on
    assert_nil @user.active_goal
    assert_redirected_to goal_periods_path
  end

  test "cannot end another user's goal" do
    foreign = users(:two).goal_periods.create!(goal_type: "build_muscle", started_on: Date.current)

    patch finish_goal_period_path(foreign)

    assert_response :not_found
    assert_nil foreign.reload.ended_on
  end
end
