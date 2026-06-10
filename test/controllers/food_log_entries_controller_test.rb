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
        # Entry persists synchronously; NutritionRecomputeJob produces the decision.
        perform_enqueued_jobs do
          post food_log_entries_path, params: {
            food_log_entry: {
              food_id: @food.id,
              quantity_grams: 250,
              logged_at: Time.current
            }
          }
        end
      end
    end

    entry = FoodLogEntry.last
    assert_equal 150, entry.kcal.to_f
    assert_equal 25, entry.protein_g.to_f
    assert_equal FoodLogEntry.meal_type_for(entry.logged_at.in_time_zone(@user.time_zone)), entry.meal_type

    @food.update!(kcal: 100, protein_g: 5)
    assert_equal 150, entry.reload.kcal.to_f
    assert_equal 25, entry.protein_g.to_f
    assert_redirected_to nutrition_path
  end

  test "turbo stream logging refreshes the live nutrition workspace" do
    post food_log_entries_path,
      params: {
        food_log_entry: {
          food_id: @food.id,
          quantity_grams: 250,
          logged_at: Time.current
        }
      },
      as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, 'target="nutrition_log"'
    assert_includes response.body, "Greek Yogurt"
    assert_includes response.body, "25 g protein"
  end

  test "deletes only the current user's food log through turbo stream" do
    entry = @user.food_log_entries.create!(
      food: @food,
      logged_at: Time.current,
      quantity_grams: 100,
      kcal: 60,
      protein_g: 10,
      carb_g: 4,
      fat_g: 0
    )

    assert_difference "FoodLogEntry.count", -1 do
      delete food_log_entry_path(entry), as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, 'target="nutrition_log"'
  end

  test "updates quantity and meal while recalculating the macro snapshot" do
    entry = @user.food_log_entries.create!(
      food: @food,
      logged_at: Time.current,
      meal_type: "breakfast",
      quantity_grams: 100,
      kcal: 60,
      protein_g: 10,
      carb_g: 4,
      fat_g: 0
    )

    patch food_log_entry_path(entry),
      params: {
        food_log_entry: {
          quantity_grams: 250,
          meal_type: "lunch"
        }
      },
      as: :turbo_stream

    assert_response :success
    assert_equal "lunch", entry.reload.meal_type
    assert_equal 150, entry.kcal.to_f
    assert_equal 25, entry.protein_g.to_f
    assert_includes response.body, "Lunch"
    assert_includes response.body, "150 kcal"
  end

  test "cannot update another user's food log" do
    entry = users(:two).food_log_entries.create!(
      food: @food,
      logged_at: Time.current,
      meal_type: "dinner",
      quantity_grams: 100,
      kcal: 60,
      protein_g: 10,
      carb_g: 4,
      fat_g: 0
    )

    patch food_log_entry_path(entry), params: {
      food_log_entry: {
        quantity_grams: 250,
        meal_type: "lunch"
      }
    }

    assert_response :not_found
    assert_equal 100, entry.reload.quantity_grams.to_f
  end

  test "updates a quick entry by scaling its existing macro snapshot" do
    entry = @user.food_log_entries.create!(
      logged_at: Time.current,
      meal_type: "snack",
      quantity_grams: 100,
      kcal: 200,
      protein_g: 20,
      carb_g: 25,
      fat_g: 4
    )

    patch food_log_entry_path(entry),
      params: {
        food_log_entry: {
          quantity_grams: 150,
          meal_type: "snack"
        }
      },
      as: :turbo_stream

    assert_response :success
    assert_equal 300, entry.reload.kcal.to_f
    assert_equal 30, entry.protein_g.to_f
  end

  test "copies yesterday once while preserving meals and local clock times" do
    @user.update!(time_zone: "America/Denver")
    today = @user.local_date
    yesterday_at_lunch = Time.use_zone(@user.time_zone) do
      Time.zone.local(today.yesterday.year, today.yesterday.month, today.yesterday.day, 12, 30)
    end
    source = @user.food_log_entries.create!(
      food: @food,
      logged_at: yesterday_at_lunch,
      meal_type: "lunch",
      quantity_grams: 200,
      kcal: 120,
      protein_g: 20,
      carb_g: 8,
      fat_g: 0
    )

    assert_difference "FoodLogEntry.count", 1 do
      post copy_yesterday_food_log_entries_path, as: :turbo_stream
    end

    copied = @user.food_log_entries.find_by!(copied_from_entry: source)
    assert_equal "lunch", copied.meal_type
    assert_equal 200, copied.quantity_grams.to_f
    assert_equal today, @user.local_date_at(copied.logged_at)
    assert_equal [ 12, 30 ], [ copied.logged_at.in_time_zone(@user.time_zone).hour, copied.logged_at.in_time_zone(@user.time_zone).min ]
    assert_includes response.body, "1 entry copied from yesterday."

    assert_no_difference "FoodLogEntry.count" do
      post copy_yesterday_food_log_entries_path, as: :turbo_stream
    end

    assert_includes response.body, "Yesterday’s food is already copied."
  end

  test "groups today's entries by meal in the live workspace" do
    @user.food_log_entries.create!(
      food: @food,
      logged_at: Time.current,
      meal_type: "breakfast",
      quantity_grams: 100,
      kcal: 60,
      protein_g: 10,
      carb_g: 4,
      fat_g: 0
    )

    get nutrition_path

    assert_response :success
    assert_select ".meal-group h3", text: "Breakfast"
    assert_select ".nutrition-entry", count: 1
    assert_select "form[action='#{food_log_entry_path(FoodLogEntry.last)}']"
  end
end
