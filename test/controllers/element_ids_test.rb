require "test_helper"

# Turbo matches morph-permanent elements with `getElementById`, so an id that
# appears twice makes a background refresh preserve whichever copy it finds
# first. Rails names a field after its model rather than after the record, which
# is how the nutrition page came to render `food_log_entry_quantity_grams` once
# per logged entry, once per one-tap button, and once for the manual form.
#
# This is server-rendered markup, so it is checked here rather than in a browser.
class ElementIdsTest < ActionDispatch::IntegrationTest
  include AccountFixture

  setup do
    @user = users(:one)
    populate_account(@user)
    # populate_account logs food on past days, and the loops that repeat markup
    # are the ones rendering *today*: two entries in the same meal is what made
    # the nutrition page render one id three times.
    # Two entries in one meal, and a second meal, because both loops repeat
    # markup: one form per entry, and one "save as a meal" form per group.
    { "breakfast" => 2, "lunch" => 1 }.each do |meal_type, count|
      count.times do |index|
        @user.food_log_entries.create!(
          food: @user.foods.first, logged_at: Time.current - index.minutes, meal_type: meal_type,
          quantity_grams: 80 + index, source: "manual", kcal: 100, protein_g: 5, carb_g: 10, fat_g: 2
        )
      end
    end
    sign_in_as(@user)
  end

  test "no page renders the same element id twice" do
    pages.each do |path|
      get path
      assert_response :success, "#{path} did not render"

      duplicates = css_select("[id]")
        .map { |element| element["id"] }
        .tally
        .select { |_id, count| count > 1 }

      assert_empty duplicates, "#{path} renders duplicate ids"
    end
  end

  private

  # Every authenticated page that renders a record the user owns, so the loops
  # that produce repeated markup actually run.
  def pages
    [
      root_path, nutrition_path, meals_path, new_meal_path,
      edit_meal_path(@user.meals.first), progress_path, onboarding_path,
      readiness_inputs_path, edit_readiness_input_path(@user.daily_readiness_inputs.first),
      goal_periods_path, weekly_review_path, wearable_devices_path,
      mesocycles_path, exercises_path, new_exercise_path,
      exercise_path(@user.exercises.first), exercise_prescriptions_path,
      new_exercise_prescription_path,
      edit_exercise_prescription_path(@user.exercise_prescriptions.first),
      workout_templates_path, new_workout_template_path,
      edit_workout_template_path(@user.workout_templates.first),
      workout_sessions_path, new_workout_session_path,
      workout_session_path(@user.workout_sessions.first),
      edit_workout_session_path(@user.workout_sessions.first),
      conditioning_sessions_path,
      coaching_decision_path(@user.coaching_decisions.first),
      edit_profile_path, edit_food_path(@user.foods.first)
    ]
  end
end
