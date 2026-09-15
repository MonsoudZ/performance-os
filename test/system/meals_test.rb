require "application_system_test_case"

# A meal is the nutrition side of saving a session as a workout: the second time
# you eat the same thing should cost a tap rather than four rows of typing. The
# form reuses the workout template editor's Stimulus controller, so what is
# worth proving here is that the reuse holds with two fields per row — an index
# rewritten on only one of them would file the grams against the wrong food.
class MealsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @oats = food("Zzz Sys Oats", kcal: 380, protein_g: 13)
    @whey = food("Zzz Sys Whey", kcal: 400, protein_g: 80)
    @banana = food("Zzz Sys Banana", kcal: 89, protein_g: 1)
  end

  test "builds a meal out of foods added one at a time" do
    sign_in @user
    visit new_meal_path

    fill_in "Meal name", with: "Zzz Sys Breakfast"

    select "Zzz Sys Oats", from: food_select_name(0)
    set_number grams_field(0), 80
    click_on "Add food"
    select "Zzz Sys Whey", from: food_select_name(1)
    set_number grams_field(1), 30
    click_on "Add food"
    select "Zzz Sys Banana", from: food_select_name(2)
    set_number grams_field(2), 120

    assert_selector ".template-editor__row", count: 3

    click_on "Save meal"
    assert_current_path meals_path, wait: 10

    meal = @user.meals.find_by!(name: "Zzz Sys Breakfast")
    portions = meal.meal_items.order(:position).map { |item| [ item.food.name, item.quantity_grams.to_i ] }

    assert_equal [ [ "Zzz Sys Oats", 80 ], [ "Zzz Sys Whey", 30 ], [ "Zzz Sys Banana", 120 ] ], portions,
      "each row's grams stayed with the food it was typed next to"
  end

  test "one tap logs every food in the meal" do
    meal = @user.meals.new(name: "Zzz Sys Shake")
    meal.meal_items.build(food: @whey, quantity_grams: 30, position: 1)
    meal.meal_items.build(food: @banana, quantity_grams: 120, position: 2)
    meal.save!

    sign_in @user
    visit nutrition_path

    assert_text "No food logged today"
    click_on(class: "recent-food--meal", match: :first)

    # The entries panel is a Turbo frame, so both foods appear without a reload.
    assert_text "Zzz Sys Whey", wait: 10
    assert_text "Zzz Sys Banana"
    assert_equal 2, @user.food_log_entries.count
  end

  test "a meal already eaten is kept from the log" do
    sign_in @user
    log(@oats, grams: 80)
    log(@whey, grams: 30)
    visit nutrition_path

    click_on "Save as a meal"

    # Lands in the editor, where the portions are the thing worth adjusting.
    meal = @user.meals.sole
    assert_current_path edit_meal_path(meal), wait: 10
    assert_equal [ 80, 30 ], meal.meal_items.order(:position).map { |item| item.quantity_grams.to_i }
  end

  private

  def food(name, kcal:, protein_g:)
    @user.foods.create!(name: name, serving_grams: 100, kcal: kcal, protein_g: protein_g, carb_g: 10, fat_g: 5)
  end

  def log(item, grams:)
    @user.food_log_entries.create!(
      food: item, logged_at: Time.current, quantity_grams: grams, source: "manual",
      **item.macros_for(grams)
    )
  end

  def food_select_name(index)
    all(".template-editor__row select")[index][:name]
  end

  def grams_field(index)
    all(".template-editor__row input[type='number']")[index]
  end
end
