require "test_helper"

class FoodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "creates a food in the user's catalog" do
    assert_difference "Food.count", 1 do
      post foods_path, params: {
        food: { name: "Cottage Cheese", serving_grams: 100, kcal: 98, protein_g: 11, carb_g: 3, fat_g: 4 }
      }
    end

    food = Food.order(:id).last
    assert_equal @user, food.user
    assert_redirected_to nutrition_path
  end

  test "rejects an invalid food" do
    assert_no_difference "Food.count" do
      post foods_path, params: {
        food: { name: "", serving_grams: 0, kcal: -1, protein_g: 0, carb_g: 0, fat_g: 0 }
      }
    end

    assert_redirected_to nutrition_path
    assert_equal flash[:alert].present?, true
  end

  test "edits an existing food without touching logged entries" do
    food = @user.foods.create!(name: "Oats", serving_grams: 40, kcal: 150, protein_g: 5, carb_g: 27, fat_g: 3)
    entry = @user.food_log_entries.create!(
      food: food, logged_at: Time.current, meal_type: "breakfast",
      quantity_grams: 40, source: "manual", **food.macros_for(40)
    )

    patch food_path(food), params: { food: { name: "Oats", serving_grams: 40, kcal: 200, protein_g: 5, carb_g: 27, fat_g: 3 } }

    assert_equal 200, food.reload.kcal.to_f
    # Logged entry keeps its snapshotted macros.
    assert_equal 150, entry.reload.kcal.to_f
    assert_redirected_to nutrition_path
  end

  test "deletes a food and nullifies its log entries" do
    food = @user.foods.create!(name: "Rice Cake", serving_grams: 10, kcal: 35, protein_g: 1, carb_g: 7, fat_g: 0)
    entry = @user.food_log_entries.create!(
      food: food, logged_at: Time.current, meal_type: "snack",
      quantity_grams: 10, source: "manual", **food.macros_for(10)
    )

    assert_difference "Food.count", -1 do
      delete food_path(food)
    end

    assert_nil entry.reload.food_id
    assert_equal 35, entry.kcal.to_f
    assert_redirected_to nutrition_path
  end

  test "cannot edit another user's food" do
    foreign = users(:two).foods.create!(name: "Secret Sauce", serving_grams: 20, kcal: 90, protein_g: 0, carb_g: 2, fat_g: 9)

    get edit_food_path(foreign)

    assert_response :not_found
  end

  test "cannot edit a shared catalog food" do
    shared = Food.create!(name: "Shared Apple", serving_grams: 100, kcal: 52, protein_g: 0, carb_g: 14, fat_g: 0)

    get edit_food_path(shared)

    assert_response :not_found
  end

  test "searches the food database and renders results" do
    result = FoodDatabaseSearch::Result.new(
      name: "Greek Yogurt", brand: "Fage", serving_grams: 100,
      kcal: 59, protein_g: 10, carb_g: 4, fat_g: 0, code: "1"
    )

    with_search_results([ result ]) do
      get search_foods_path, params: { q: "yogurt" }
    end

    assert_response :success
    assert_select ".food-result", 1
    assert_select "strong", text: "Fage · Greek Yogurt"
  end

  test "a blank search renders no results and does not call the database" do
    get search_foods_path, params: { q: "" }

    assert_response :success
    assert_select ".food-result", count: 0
  end

  test "imports a database result into the catalog as an imported food" do
    assert_difference "Food.count", 1 do
      post import_foods_path, params: {
        q: "yogurt",
        food: { name: "Greek Yogurt", brand: "Fage", serving_grams: 100, kcal: 59, protein_g: 10.3, carb_g: 3.6, fat_g: 0.4 }
      }
    end

    food = Food.order(:id).last
    assert_equal @user, food.user
    assert_equal "import", food.source
    assert_equal "Greek Yogurt", food.name
    assert_redirected_to nutrition_path
  end

  private

  # Swaps the external search with canned results for the block (no
  # Minitest::Mock available in this build).
  def with_search_results(results)
    fake = Object.new
    fake.define_singleton_method(:call) { results }
    FoodDatabaseSearch.define_singleton_method(:new) { |*, **| fake }
    yield
  ensure
    FoodDatabaseSearch.singleton_class.send(:remove_method, :new)
  end
end
