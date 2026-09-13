require "test_helper"

class OnboardingProgressTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Zzz Onboarding Squat", modality: "barbell")
  end

  test "a brand-new account has everything outstanding" do
    progress = OnboardingProgress.new(@user)

    assert_not progress.complete?
    assert_equal %i[goal target check_in], progress.remaining.map(&:key)
    assert_equal :goal, progress.next_step.key
    assert progress.steps.none?(&:done?)
  end

  test "pairing a watch is never what stands between a user and a plan" do
    device_step = OnboardingProgress.new(@user).steps.find { |step| step.key == :device }

    assert_predicate device_step, :optional?
    assert_not_includes OnboardingProgress.new(@user).remaining, device_step
  end

  test "setup is complete once a goal and either a target or a check-in exist" do
    set_goal

    assert_not OnboardingProgress.new(@user).complete?, "a goal alone produces no plan"

    prescribe

    assert_predicate OnboardingProgress.new(@user), :complete?
  end

  test "a check-in counts instead of a target, because it alone yields a plan" do
    set_goal
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2
    )

    progress = OnboardingProgress.new(@user)

    assert_predicate progress, :complete?
    assert_equal [ :target ], progress.remaining.map(&:key),
      "the step is still outstanding even though setup no longer blocks on it"
  end

  test "a completed step points at managing it rather than creating it again" do
    prescribe
    step = OnboardingProgress.new(@user).steps.find { |s| s.key == :target }

    assert_predicate step, :done?
    assert_equal exercise_prescriptions_path, step.path
    assert_equal "Manage targets", step.cta
  end

  test "an outstanding step names the action that clears it" do
    step = OnboardingProgress.new(@user).steps.find { |s| s.key == :target }

    assert_not step.done?
    assert_equal new_exercise_prescription_path, step.path
    assert_equal "Add a target", step.cta
  end

  test "the goal step reflects the goal once one is set" do
    set_goal(goal_type: "lose_fat")
    step = OnboardingProgress.new(@user).steps.find { |s| s.key == :goal }

    assert_predicate step, :done?
    assert_match(/lose fat/, step.prompt)
  end

  test "an ended goal leaves the step outstanding again" do
    goal = @user.goal_periods.create!(goal_type: "build_muscle", started_on: 30.days.ago.to_date)
    goal.update!(ended_on: 1.day.ago.to_date)

    assert_not OnboardingProgress.new(@user).steps.first.done?
  end

  test "next_step is nil when nothing required is outstanding" do
    set_goal
    prescribe
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2
    )

    progress = OnboardingProgress.new(@user)

    assert_empty progress.remaining
    assert_nil progress.next_step
  end

  private

  def set_goal(goal_type: "build_muscle")
    @user.goal_periods.create!(goal_type: goal_type, started_on: Date.current)
  end

  def prescribe
    @user.exercise_prescriptions.create!(
      exercise: @exercise, rep_min: 6, rep_max: 8,
      target_rir_min: 1, target_rir_max: 2, increment_kg: 2.5,
      working_sets: 3, started_on: Date.current
    )
  end
end
