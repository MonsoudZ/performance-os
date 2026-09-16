require "test_helper"

# Building and editing a meal from the phone.
#
# The foods arrive as nested attributes, the same shape the web editor posts, so
# the two share one set of rules about what a meal is. The contract worth
# guarding is what a partial payload means: an item left out is kept, not
# deleted, because a dropped field should not erase somebody's breakfast.
class Api::V1::NativeMealsApiTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @token = sign_in_natively
    @oats = food("Zzz Meal Api Oats")
    @whey = food("Zzz Meal Api Whey")
    @rice = food("Zzz Meal Api Rice")
  end

  teardown { Rack::Attack.reset! }

  # ---- building one -----------------------------------------------------

  test "a meal is built from an ordered list of foods and portions" do
    assert_difference "Meal.count", 1 do
      assert_difference "MealItem.count", 2 do
        post api_v1_meals_path, headers: auth, as: :json, params: { meal: {
          name: "Zzz Api Breakfast",
          meal_items_attributes: [
            { food_id: @oats.id, quantity_grams: 80 },
            { food_id: @whey.id, quantity_grams: 30 }
          ]
        } }
      end
    end

    assert_response :created
    meal = response.parsed_body.fetch("data")
    assert_equal "Zzz Api Breakfast", meal.fetch("name")
    assert_equal [ @oats.id, @whey.id ], meal.fetch("items").map { |i| i.dig("food", "id") }
    # The client sends an ordered list; it does not have to number it.
    assert_equal [ 1, 2 ], meal.fetch("items").pluck("position")
  end

  test "the totals are computed from the foods rather than stored on the meal" do
    meal = build_meal("Zzz Api Totals")

    get api_v1_meal_path(meal), headers: auth, as: :json

    assert_response :success
    # 80 g oats + 30 g whey, both 100 g servings.
    assert_in_delta 418.0, response.parsed_body.dig("data", "totals", "kcal"), 0.5

    # Correcting the food corrects every meal built on it, rather than leaving
    # a stale copy behind: 80 g at 500 kcal/100 g, plus the unchanged 30 g.
    @oats.update!(kcal: 500)
    get api_v1_meal_path(meal), headers: auth, as: :json
    assert_in_delta 514.0, response.parsed_body.dig("data", "totals", "kcal"), 0.5
  end

  test "a meal with no foods is refused rather than saved empty" do
    assert_no_difference "Meal.count" do
      post api_v1_meals_path, headers: auth, as: :json, params: { meal: { name: "Zzz Api Empty" } }
    end

    assert_response :unprocessable_entity
    assert_match(/food/i, response.parsed_body.fetch("details").join(" "))
  end

  test "a name already taken is refused rather than silently renamed" do
    build_meal("Zzz Api Taken")

    assert_no_difference "Meal.count" do
      post api_v1_meals_path, headers: auth, as: :json, params: { meal: {
        name: "Zzz Api Taken",
        meal_items_attributes: [ { food_id: @oats.id, quantity_grams: 80 } ]
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/name/i, response.parsed_body.fetch("details").join(" "))
  end

  test "a food this account cannot see cannot be put in its meal" do
    theirs = users(:two).foods.create!(
      name: "Zzz Api Not Mine", serving_grams: 100, kcal: 1, protein_g: 1, carb_g: 1, fat_g: 1
    )

    assert_no_difference "Meal.count" do
      post api_v1_meals_path, headers: auth, as: :json, params: { meal: {
        name: "Zzz Api Borrowed",
        meal_items_attributes: [ { food_id: theirs.id, quantity_grams: 80 } ]
      } }
    end

    assert_response :unprocessable_entity
  end

  # The unique index rejected this, but only after validation had passed — the
  # per-item uniqueness check only sees rows already in the table, so two new
  # ones naming the same food both got through and the database said no. That
  # reached the user as a 500 from the editor rather than as a sentence.
  test "the same food twice in one meal is refused with its reason" do
    assert_no_difference "Meal.count" do
      post api_v1_meals_path, headers: auth, as: :json, params: { meal: {
        name: "Zzz Api Doubled",
        meal_items_attributes: [
          { food_id: @oats.id, quantity_grams: 80 },
          { food_id: @oats.id, quantity_grams: 40 }
        ]
      } }
    end

    assert_response :unprocessable_entity
    assert_match(/same food twice/i, response.parsed_body.fetch("details").join(" "))
  end

  # ---- editing one ------------------------------------------------------

  test "a portion is corrected without touching the rest of the meal" do
    meal = build_meal("Zzz Api Editable")
    oats_item = meal.meal_items.order(:position).first

    patch api_v1_meal_path(meal), headers: auth, as: :json, params: { meal: {
      meal_items_attributes: [ { id: oats_item.id, quantity_grams: 120 } ]
    } }

    assert_response :success
    assert_equal 120.0, oats_item.reload.quantity_grams.to_f
    # The item the payload never mentioned is still there.
    assert_equal 2, meal.meal_items.reload.count
  end

  test "a food is added to a meal without renumbering the ones already in it" do
    meal = build_meal("Zzz Api Growable")

    patch api_v1_meal_path(meal), headers: auth, as: :json, params: { meal: {
      meal_items_attributes: [ { food_id: @rice.id, quantity_grams: 150 } ]
    } }

    assert_response :success
    items = response.parsed_body.dig("data", "items")
    assert_equal [ @oats.id, @whey.id, @rice.id ], items.map { |i| i.dig("food", "id") }
    assert_equal [ 1, 2, 3 ], items.pluck("position")
  end

  test "a food is removed only when the payload says so" do
    meal = build_meal("Zzz Api Shrinkable")
    whey_item = meal.meal_items.order(:position).second

    assert_difference "MealItem.count", -1 do
      patch api_v1_meal_path(meal), headers: auth, as: :json, params: { meal: {
        meal_items_attributes: [ { id: whey_item.id, _destroy: true } ]
      } }
    end

    assert_response :success
    items = response.parsed_body.dig("data", "items")
    assert_equal [ @oats.id ], items.map { |i| i.dig("food", "id") }
    # Removing the second of two leaves the first at 1, not at 2.
    assert_equal [ 1 ], items.pluck("position")
  end

  # The web editor's move buttons write a position per row, and so can a client.
  # A persisted meal loads its foods in their *old* order and nested attributes
  # update them in place, so numbering by that order rather than by the
  # submitted one throws every reorder away.
  test "reordering the foods survives the save" do
    meal = build_meal("Zzz Api Reorderable")
    first, second = meal.meal_items.order(:position).to_a

    patch api_v1_meal_path(meal), headers: auth, as: :json, params: { meal: {
      meal_items_attributes: [
        { id: second.id, position: 1 },
        { id: first.id, position: 2 }
      ]
    } }

    assert_response :success
    assert_equal [ @whey.id, @oats.id ],
      response.parsed_body.dig("data", "items").map { |i| i.dig("food", "id") }
  end

  test "emptying a meal by removing every food is refused" do
    meal = build_meal("Zzz Api Emptyable")

    assert_no_difference "MealItem.count" do
      patch api_v1_meal_path(meal), headers: auth, as: :json, params: { meal: {
        meal_items_attributes: meal.meal_items.map { |item| { id: item.id, _destroy: true } }
      } }
    end

    assert_response :unprocessable_entity
  end

  test "renaming a meal leaves its foods alone" do
    meal = build_meal("Zzz Api Renamable")

    patch api_v1_meal_path(meal), headers: auth, as: :json,
      params: { meal: { name: "Zzz Api Renamed" } }

    assert_response :success
    assert_equal "Zzz Api Renamed", meal.reload.name
    assert_equal 2, meal.meal_items.count
  end

  # ---- removing one -----------------------------------------------------

  test "deleting a meal leaves the entries it already logged alone" do
    meal = build_meal("Zzz Api Deletable")
    post log_api_v1_meal_path(meal), headers: auth, as: :json
    assert_response :created

    assert_difference "Meal.count", -1 do
      assert_no_difference "FoodLogEntry.count" do
        delete api_v1_meal_path(meal), headers: auth, as: :json
      end
    end

    assert_response :no_content
  end

  # ---- keeping a meal already eaten -------------------------------------

  test "a logged sitting is saved as a meal, one line per food" do
    log(@oats, grams: 80, meal_type: "breakfast")
    log(@whey, grams: 30, meal_type: "breakfast")
    log(@rice, grams: 150, meal_type: "dinner")

    assert_difference "Meal.count", 1 do
      post api_v1_meal_from_log_path, headers: auth, as: :json,
        params: { date: @user.local_date.iso8601, meal_type: "breakfast", name: "Zzz Api From Log" }
    end

    assert_response :created
    meal = response.parsed_body.fetch("data")
    assert_equal "Zzz Api From Log", meal.fetch("name")
    assert_equal [ @oats.id, @whey.id ], meal.fetch("items").map { |i| i.dig("food", "id") }
    assert_equal [ 80.0, 30.0 ], meal.fetch("items").pluck("quantity_grams")
  end

  # Eating the same thing twice in a sitting is one portion of it, not two rows
  # that would collide on the meal's unique index.
  test "a food eaten twice in one sitting becomes one line with the total" do
    log(@oats, grams: 80, meal_type: "lunch")
    log(@oats, grams: 40, meal_type: "lunch")

    post api_v1_meal_from_log_path, headers: auth, as: :json,
      params: { date: @user.local_date.iso8601, meal_type: "lunch", name: "Zzz Api Doubled Up" }

    assert_response :created
    items = response.parsed_body.dig("data", "items")
    assert_equal 1, items.length
    assert_equal 120.0, items.sole.fetch("quantity_grams")
  end

  test "the name is suggested and steps around one already taken" do
    log(@oats, grams: 80, meal_type: "breakfast")

    2.times do
      post api_v1_meal_from_log_path, headers: auth, as: :json,
        params: { date: @user.local_date.iso8601, meal_type: "breakfast" }
      assert_response :created
    end

    assert_equal [ "Breakfast", "Breakfast 2" ], @user.meals.order(:id).pluck(:name)
  end

  test "saving a day nothing was logged in is refused rather than saved empty" do
    assert_no_difference "Meal.count" do
      post api_v1_meal_from_log_path, headers: auth, as: :json,
        params: { date: @user.local_date.iso8601, name: "Zzz Api Nothing" }
    end

    assert_response :unprocessable_entity
  end

  test "a date that will not parse is refused rather than read as today" do
    post api_v1_meal_from_log_path, headers: auth, as: :json, params: { date: "yesterday" }

    assert_response :bad_request
  end

  # ---- somebody else's meals --------------------------------------------

  test "another account's meal is a 404 to read, edit or delete" do
    theirs = users(:two).meals.create!(
      name: "Zzz Api Theirs",
      meal_items_attributes: [ { food_id: catalog_food.id, quantity_grams: 80, position: 1 } ]
    )

    get api_v1_meal_path(theirs), headers: auth, as: :json
    assert_response :not_found

    patch api_v1_meal_path(theirs), headers: auth, as: :json, params: { meal: { name: "Zzz Api Mine Now" } }
    assert_response :not_found
    assert_equal "Zzz Api Theirs", theirs.reload.name

    delete api_v1_meal_path(theirs), headers: auth, as: :json
    assert_response :not_found
    assert theirs.reload.persisted?
  end

  test "every meal endpoint refuses an unauthenticated request" do
    meal = build_meal("Zzz Api Guarded")

    get api_v1_meal_path(meal), as: :json
    assert_response :unauthorized

    post api_v1_meals_path, as: :json, params: { meal: { name: "Zzz Api Nope" } }
    assert_response :unauthorized

    patch api_v1_meal_path(meal), as: :json, params: { meal: { name: "Zzz Api Nope" } }
    assert_response :unauthorized

    delete api_v1_meal_path(meal), as: :json
    assert_response :unauthorized

    post api_v1_meal_from_log_path, as: :json
    assert_response :unauthorized
  end

  private

  def sign_in_natively
    post api_v1_session_path, params: { email_address: @user.email_address, password: "password" }, as: :json
    response.parsed_body.fetch("token")
  end

  def auth(token = @token)
    { "Authorization" => "Bearer #{token}" }
  end

  def food(name)
    @user.foods.create!(name: name, serving_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7)
  end

  def catalog_food
    Food.create!(name: "Zzz Api Catalog #{SecureRandom.hex(3)}", serving_grams: 100,
      kcal: 100, protein_g: 5, carb_g: 10, fat_g: 2)
  end

  def build_meal(name)
    meal = @user.meals.new(name: name)
    meal.meal_items.build(food: @oats, quantity_grams: 80, position: 1)
    meal.meal_items.build(food: @whey, quantity_grams: 30, position: 2)
    meal.save!
    meal
  end

  def log(item, grams:, meal_type:)
    @user.food_log_entries.create!(
      food: item, logged_at: Time.current, meal_type: meal_type, quantity_grams: grams,
      source: "manual", **item.macros_for(grams)
    )
  end
end
