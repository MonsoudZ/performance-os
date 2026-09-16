require "test_helper"

# One rule, because two places prefill a name and both have to step around one
# already taken: saving breakfast on two different days, or running the same
# split twice, is the ordinary case, and a prefilled collision would be a
# validation error on something the user never typed.
class AvailableNameTest < ActiveSupport::TestCase
  test "a free name is left alone" do
    assert_equal "Breakfast", AvailableName.for("Breakfast", taken: [ "Lunch" ])
  end

  test "a taken name gets the first free suffix, not the next integer" do
    assert_equal "Breakfast 2", AvailableName.for("Breakfast", taken: [ "Breakfast" ])
    assert_equal "Breakfast 3", AvailableName.for("Breakfast", taken: [ "Breakfast", "Breakfast 2" ])
    # The gap is reused rather than counted past.
    assert_equal "Breakfast 2", AvailableName.for("Breakfast", taken: [ "Breakfast", "Breakfast 3" ])
  end

  test "both callers step around a taken name the same way" do
    user = users(:one)
    oats = user.foods.create!(name: "Zzz Name Oats", serving_grams: 100, kcal: 380,
      protein_g: 13, carb_g: 67, fat_g: 7)
    entry = user.food_log_entries.create!(food: oats, logged_at: Time.current, meal_type: "breakfast",
      quantity_grams: 80, source: "manual", **oats.macros_for(80))
    user.meals.create!(name: "Breakfast",
      meal_items_attributes: [ { food_id: oats.id, quantity_grams: 80, position: 1 } ])
    assert_equal "Breakfast 2", MealFromLoggedEntries.suggested_name(user, [ entry ])

    squat = Exercise.find_or_create_by!(name: "Zzz Name Squat") { |e| e.modality = "barbell" }
    session = user.workout_sessions.create!(performed_at: Time.current)
    session.set_entries.create!(exercise: squat, set_index: 1, weight_kg: 100, reps: 5, rir: 2)
    taken = WorkoutTemplateFromSession.suggested_name(session)
    user.workout_templates.create!(name: taken, weekdays: [ 1 ],
      workout_template_exercises_attributes: [ { exercise_id: squat.id, position: 1 } ])

    assert_equal "#{taken} 2", WorkoutTemplateFromSession.suggested_name(session)
  end
end
