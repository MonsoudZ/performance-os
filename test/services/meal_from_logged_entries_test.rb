require "test_helper"

class MealFromLoggedEntriesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @oats = food("Zzz Saved Oats")
    @whey = food("Zzz Saved Whey")
  end

  test "keeps each food and the portion that was eaten" do
    entries = [ log(@oats, grams: 80), log(@whey, grams: 30) ]

    meal = MealFromLoggedEntries.new(@user, entries, name: "Zzz Saved Breakfast").call

    assert meal.persisted?
    assert_equal [ @oats.id, @whey.id ], meal.meal_items.order(:position).pluck(:food_id)
    assert_equal [ 80, 30 ], meal.meal_items.order(:position).map { |item| item.quantity_grams.to_i }
  end

  # Eating the same thing twice in one sitting is one portion of it, not two
  # rows — which would collide on the meal's unique index.
  test "the same food logged twice becomes one portion" do
    entries = [ log(@oats, grams: 50), log(@oats, grams: 30) ]

    meal = MealFromLoggedEntries.new(@user, entries, name: "Zzz Saved Double").call

    assert meal.persisted?
    assert_equal 1, meal.meal_items.size
    assert_equal 80, meal.meal_items.first.quantity_grams.to_i
  end

  test "a name already taken is rejected rather than silently renamed" do
    existing = @user.meals.new(name: "Zzz Saved Clash")
    existing.meal_items.build(food: @oats, quantity_grams: 10, position: 1)
    existing.save!

    meal = MealFromLoggedEntries.new(@user, [ log(@whey, grams: 30) ], name: "Zzz Saved Clash").call

    assert_not meal.persisted?
    assert_match(/name/i, meal.errors.full_messages.to_sentence)
  end

  test "the suggested name steps around one already taken" do
    entries = [ log(@oats, grams: 80, meal_type: "breakfast") ]

    assert_equal "Breakfast", MealFromLoggedEntries.suggested_name(@user, entries)
    MealFromLoggedEntries.new(@user, entries).call
    assert_equal "Breakfast 2", MealFromLoggedEntries.suggested_name(@user, entries)
  end

  # A quick entry with no food behind it has no portion to keep.
  test "entries with no food are skipped" do
    entries = [ log(@oats, grams: 80), log(nil, grams: 40) ]

    meal = MealFromLoggedEntries.new(@user, entries, name: "Zzz Saved Partial").call

    assert_equal [ @oats.id ], meal.meal_items.pluck(:food_id)
  end

  private

  def food(name)
    @user.foods.create!(name: name, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7, serving_grams: 100)
  end

  def log(food, grams:, meal_type: "breakfast")
    @user.food_log_entries.create!(
      food: food, logged_at: Time.current, meal_type: meal_type, quantity_grams: grams,
      source: "manual", kcal: 100, protein_g: 5, carb_g: 10, fat_g: 2
    )
  end
end
