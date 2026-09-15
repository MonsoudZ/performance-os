require "test_helper"

class MealsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @oats = food("Zzz Meals Oats")
    @whey = food("Zzz Meals Whey")
  end

  test "builds a meal out of several foods" do
    assert_difference "Meal.count", 1 do
      post meals_path, params: { meal: {
        name: "Zzz Built Breakfast",
        meal_items_attributes: {
          "0" => { food_id: @oats.id, quantity_grams: 80 },
          "1" => { food_id: @whey.id, quantity_grams: 30 }
        }
      } }
    end

    meal = Meal.order(:id).last
    assert_redirected_to meals_path
    # The form does not ask for an order; the rows arrive in one.
    assert_equal [ [ @oats.id, 1 ], [ @whey.id, 2 ] ], meal.meal_items.map { |item| [ item.food_id, item.position ] }
  end

  test "a meal with no foods is rejected rather than saved empty" do
    assert_no_difference "Meal.count" do
      post meals_path, params: { meal: { name: "Zzz Empty" } }
    end

    assert_response :unprocessable_entity
  end

  test "another account's meal is a 404" do
    meal = meal_for(users(:two), "Zzz Someone Elses")

    get edit_meal_path(meal)
    assert_response :not_found

    post log_meal_path(meal)
    assert_response :not_found
  end

  test "logging a meal writes one entry per food and recomputes nutrition" do
    meal = meal_for(@user, "Zzz Tapped")

    assert_difference "FoodLogEntry.count", 2 do
      perform_enqueued_jobs do
        post log_meal_path(meal), as: :turbo_stream
      end
    end

    assert_response :success
    assert_equal [ "meal" ], FoodLogEntry.last(2).map(&:source).uniq
    assert_match "nutrition_log", response.body
  end

  test "saving a logged meal keeps its foods and portions" do
    log(@oats, grams: 80)
    log(@whey, grams: 30)

    assert_difference "Meal.count", 1 do
      post meal_from_log_path, params: {
        date: @user.local_date.iso8601, meal_type: "breakfast", name: "Zzz Saved From Log"
      }
    end

    meal = Meal.order(:id).last
    assert_redirected_to edit_meal_path(meal)
    assert_equal [ 80, 30 ], meal.meal_items.map { |item| item.quantity_grams.to_i }
  end

  test "a name already taken comes back as an alert rather than a rename" do
    meal_for(@user, "Zzz Taken")
    log(@oats, grams: 80)

    assert_no_difference "Meal.count" do
      post meal_from_log_path, params: {
        date: @user.local_date.iso8601, meal_type: "breakfast", name: "Zzz Taken"
      }
    end

    assert_redirected_to nutrition_path
    assert_match(/name/i, flash[:alert])
  end

  test "deleting a meal leaves the entries it logged alone" do
    meal = meal_for(@user, "Zzz Deletable")
    perform_enqueued_jobs { post log_meal_path(meal) }

    assert_difference "Meal.count", -1 do
      assert_no_difference "FoodLogEntry.count" do
        delete meal_path(meal)
      end
    end
  end

  private

  def food(name)
    @user.foods.create!(name: name, serving_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7)
  end

  # Built for whoever owns it: a catalog food belongs to nobody, so it is
  # available to the other account too.
  def meal_for(user, name)
    foods = user == @user ? [ @oats, @whey ] : catalog_foods
    meal = user.meals.new(name: name)
    foods.each_with_index { |item, index| meal.meal_items.build(food: item, quantity_grams: 80 - (index * 50), position: index + 1) }
    meal.save!
    meal
  end

  def catalog_foods
    2.times.map do |index|
      Food.create!(name: "Zzz Catalog #{SecureRandom.hex(3)}", serving_grams: 100,
        kcal: 100, protein_g: 5, carb_g: 10, fat_g: 2)
    end
  end

  def log(food, grams:)
    @user.food_log_entries.create!(
      food: food, logged_at: Time.current, meal_type: "breakfast", quantity_grams: grams,
      source: "manual", **food.macros_for(grams)
    )
  end
end
