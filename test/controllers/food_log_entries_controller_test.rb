require "test_helper"

class FoodLogEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @user.goal_periods.create!(
      goal_type: "build_muscle",
      params: { "target_kcal" => 2_800, "target_protein_g" => 180 },
      started_on: Date.current
    )
    @food = Food.create!(
      name: "Greek Yogurt",
      serving_grams: 100,
      kcal: 60,
      protein_g: 10,
      carb_g: 4,
      fat_g: 0
    )
  end

  test "snapshots scaled macros and creates a nutrition decision" do
    assert_difference "FoodLogEntry.count", 1 do
      assert_difference "CoachingDecision.count", 1 do
        post food_log_entries_path, params: {
          food_log_entry: {
            food_id: @food.id,
            quantity_grams: 250,
            logged_at: Time.current
          }
        }
      end
    end

    entry = FoodLogEntry.last
    assert_equal 150, entry.kcal.to_f
    assert_equal 25, entry.protein_g.to_f

    @food.update!(kcal: 100, protein_g: 5)
    assert_equal 150, entry.reload.kcal.to_f
    assert_equal 25, entry.protein_g.to_f
    assert_redirected_to nutrition_path
  end
end
