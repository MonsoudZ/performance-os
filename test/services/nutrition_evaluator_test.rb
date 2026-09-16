require "test_helper"

class NutritionEvaluatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.goal_periods.create!(
      goal_type: "build_muscle",
      params: { "target_kcal" => 2_800, "target_protein_g" => 180 },
      started_on: Date.current
    )
  end

  test "reports a protein gap from snapshotted food totals" do
    @user.food_log_entries.create!(
      logged_at: Time.current,
      quantity_grams: 500,
      kcal: 2_600,
      protein_g: 120,
      carb_g: 330,
      fat_g: 80
    )

    decision = NutritionEvaluator.new(@user).call

    assert_equal "protein_low", decision.output["status"]
    assert_equal 60, decision.output.dig("remaining", "protein_g")
    assert_equal "goal_params", decision.output.dig("targets", "source")
  end

  test "is idempotent for unchanged evidence" do
    first = NutritionEvaluator.new(@user).call

    assert_no_difference "CoachingDecision.count" do
      assert_equal first, NutritionEvaluator.new(@user).call
    end
  end
  # `inputs` has to hold everything the rule read, or a re-run short-circuits
  # onto a conclusion that has moved on. Naming the entries by id alone meant
  # correcting a portion left the id set identical — and the page reads its
  # totals off the decision, so the correction never reached the user.
  test "correcting a portion is a new conclusion, not the old one" do
    food = @user.foods.create!(name: "Zzz Eval Oats", serving_grams: 100, kcal: 400,
      protein_g: 10, carb_g: 60, fat_g: 10)
    entry = @user.food_log_entries.create!(food: food, logged_at: Time.current, meal_type: "breakfast",
      quantity_grams: 100, source: "manual", **food.macros_for(100))

    first = NutritionEvaluator.new(@user).call
    assert_in_delta 400.0, first.output.dig("totals", "kcal"), 0.1

    entry.update!(quantity_grams: 400, **entry.macros_for(400))
    second = NutritionEvaluator.new(@user).call

    assert_not_equal first.id, second.id, "the day's totals moved, so the conclusion has to"
    assert_in_delta 1600.0, second.output.dig("totals", "kcal"), 0.1
    # The totals are what the rule read; the ids are how a reader gets back to
    # the evidence behind them, which is the whole claim the table makes.
    assert_equal [ entry.id ], second.inputs.fetch("food_log_entry_ids")
  end

  test "swapping the food on an entry is a new conclusion too" do
    light = @user.foods.create!(name: "Zzz Eval Light", serving_grams: 100, kcal: 100,
      protein_g: 1, carb_g: 1, fat_g: 1)
    heavy = @user.foods.create!(name: "Zzz Eval Heavy", serving_grams: 100, kcal: 900,
      protein_g: 1, carb_g: 1, fat_g: 1)
    entry = @user.food_log_entries.create!(food: light, logged_at: Time.current, meal_type: "lunch",
      quantity_grams: 100, source: "manual", **light.macros_for(100))

    first = NutritionEvaluator.new(@user).call
    entry.update!(food: heavy, **heavy.macros_for(100))
    second = NutritionEvaluator.new(@user).call

    assert_not_equal first.id, second.id
    assert_in_delta 900.0, second.output.dig("totals", "kcal"), 0.1
  end

  test "a day that has not moved still writes nothing new" do
    food = @user.foods.create!(name: "Zzz Eval Steady", serving_grams: 100, kcal: 400,
      protein_g: 10, carb_g: 60, fat_g: 10)
    @user.food_log_entries.create!(food: food, logged_at: Time.current, meal_type: "breakfast",
      quantity_grams: 100, source: "manual", **food.macros_for(100))

    first = NutritionEvaluator.new(@user).call

    assert_no_difference "CoachingDecision.count" do
      assert_equal first.id, NutritionEvaluator.new(@user).call.id
    end
  end
end
