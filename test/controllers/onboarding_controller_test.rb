require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "renders the onboarding checklist" do
    get onboarding_path

    assert_response :success
    assert_select "h1", "Get set up in a few steps."
    assert_select ".onboarding-step", 4
  end

  test "marks completed steps as done" do
    @user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current)

    get onboarding_path

    assert_response :success
    assert_select ".onboarding-step--done", minimum: 1
  end
end
