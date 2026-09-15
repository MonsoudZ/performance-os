require "test_helper"

class MealLoggerTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "UTC")
    @oats = food("Zzz Meal Oats", kcal: 380, protein_g: 13)
    @whey = food("Zzz Meal Whey", kcal: 400, protein_g: 80)
    @meal = @user.meals.new(name: "Zzz Breakfast")
    @meal.meal_items.build(food: @oats, quantity_grams: 80, position: 1)
    @meal.meal_items.build(food: @whey, quantity_grams: 30, position: 2)
    @meal.save!
  end

  test "logs every food in the meal at its own portion" do
    entries = MealLogger.new(@meal, at: Time.zone.parse("2026-09-15 08:00")).call.entries

    assert_equal 2, entries.size
    assert_equal [ @oats.id, @whey.id ], entries.map(&:food_id)
    assert_equal [ 80, 30 ], entries.map { |entry| entry.quantity_grams.to_i }
  end

  test "macros are computed from the food and the portion" do
    entry = MealLogger.new(@meal).call.entries.first

    # 80 g of a food that is 380 kcal per 100 g.
    assert_in_delta 304.0, entry.kcal.to_f, 0.1
    assert_in_delta 10.4, entry.protein_g.to_f, 0.1
  end

  # Correcting a food should correct the meals built on it, which is why a meal
  # stores portions rather than a copy of the macros.
  test "a corrected food corrects what the meal logs" do
    @oats.update!(kcal: 400)

    entry = MealLogger.new(@meal).call.entries.first

    assert_in_delta 320.0, entry.kcal.to_f, 0.1
  end

  test "the entries are filed under the meal happening now" do
    entries = MealLogger.new(@meal, at: Time.zone.parse("2026-09-15 20:00")).call.entries

    assert_equal [ "dinner" ], entries.map(&:meal_type).uniq
  end

  # The day's evidence should not pretend four entries were typed one at a time.
  test "entries say they came from a meal" do
    assert_equal [ "meal" ], MealLogger.new(@meal).call.entries.map(&:source).uniq
  end

  private

  def food(name, kcal:, protein_g:)
    @user.foods.create!(name: name, kcal: kcal, protein_g: protein_g, carb_g: 10, fat_g: 5, serving_grams: 100)
  end
end
