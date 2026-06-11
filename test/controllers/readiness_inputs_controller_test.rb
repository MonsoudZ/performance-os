require "test_helper"

class ReadinessInputsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "lists past check-ins" do
    create_input(Date.current - 2.days)

    get readiness_inputs_path

    assert_response :success
    assert_select "h1", "Past check-ins."
  end

  test "edits a past check-in and re-evaluates readiness" do
    input = create_input(Date.current - 1.day)

    assert_enqueued_with(job: ReadinessRecomputeJob) do
      patch readiness_input_path(input), params: {
        daily_readiness_input: { sleep_hours: 8.0, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1 }
      }
    end

    assert_equal 480, input.reload.sleep_minutes
    assert_equal 5, input.sleep_quality
    assert_redirected_to readiness_inputs_path
  end

  test "cannot edit another user's check-in" do
    foreign = users(:two).daily_readiness_inputs.create!(
      metric_date: Date.current, sleep_minutes: 400, sleep_quality: 3,
      soreness: 2, fatigue: 2, stress: 2, source: "manual"
    )

    get edit_readiness_input_path(foreign)

    assert_response :not_found
  end

  private

  def create_input(date)
    @user.daily_readiness_inputs.create!(
      metric_date: date, sleep_minutes: 420, sleep_quality: 3,
      soreness: 3, fatigue: 3, stress: 3, source: "manual"
    )
  end
end
