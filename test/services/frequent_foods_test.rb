require "test_helper"

class FrequentFoodsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @now = Time.zone.parse("2026-09-15 20:00")
  end

  # The list used to be "most recently logged", so a few unusual meals pushed the
  # things you eat every day off it — exactly when you wanted them.
  test "a staple outranks something eaten once more recently" do
    oats = food("Zzz Oats")
    cake = food("Zzz Cake")
    5.times { |day| log(oats, at: @now - (day + 1).days) }
    log(cake, at: @now - 1.hour)

    assert_equal [ "Zzz Oats", "Zzz Cake" ], suggestions.map { |s| s.food.name }
  end

  test "it counts how often each one was logged" do
    oats = food("Zzz Oats")
    3.times { |day| log(oats, at: @now - (day + 1).days) }

    assert_equal 3, suggestions.first.times_logged
  end

  # Something dropped from the rotation stops being offered rather than sitting
  # there forever because it was once a habit.
  test "a food not eaten inside the window falls off" do
    old = food("Zzz Old")
    10.times { |day| log(old, at: @now - FrequentFoods::WINDOW_DAYS.days - (day + 1).days) }

    assert_empty suggestions
  end

  # The edge itself counts, so a habit logged exactly a fortnight ago is still
  # in rather than falling on which side of a boundary the clock lands.
  test "the far edge of the window is inside it" do
    edge = food("Zzz Edge")
    log(edge, at: @now - FrequentFoods::WINDOW_DAYS.days)

    assert_equal [ "Zzz Edge" ], suggestions.map { |s| s.food.name }
  end

  # The portion is the memory worth keeping: not retyping "80" every morning is
  # the whole point.
  test "it offers the portion that food was last logged at" do
    oats = food("Zzz Oats")
    log(oats, at: @now - 3.days, grams: 60)
    log(oats, at: @now - 1.day, grams: 85)

    assert_equal 85, suggestions.first.quantity_grams.to_i
  end

  test "equally frequent foods are ordered by which is still in the rotation" do
    stale = food("Zzz Stale")
    fresh = food("Zzz Fresh")
    2.times { |day| log(stale, at: @now - (day + 8).days) }
    2.times { |day| log(fresh, at: @now - (day + 1).days) }

    assert_equal [ "Zzz Fresh", "Zzz Stale" ], suggestions.map { |s| s.food.name }
  end

  test "it offers no more than the limit" do
    8.times { |n| log(food("Zzz Many #{n}"), at: @now - 1.day) }

    assert_equal FrequentFoods::LIMIT, suggestions.size
  end

  test "another account's eating habits are not suggested" do
    theirs = users(:two).foods.create!(name: "Zzz Theirs", kcal: 100, protein_g: 1, carb_g: 1, fat_g: 1, serving_grams: 100)
    users(:two).food_log_entries.create!(
      food: theirs, logged_at: @now - 1.hour, meal_type: "dinner", quantity_grams: 100,
      source: "manual", **theirs.macros_for(100)
    )

    assert_empty suggestions
  end

  private

  def suggestions = FrequentFoods.new(@user, now: @now).call

  def food(name)
    @user.foods.create!(name: name, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7, serving_grams: 100)
  end

  def log(food, at:, grams: 80)
    @user.food_log_entries.create!(
      food: food, logged_at: at, meal_type: FoodLogEntry.meal_type_for(at),
      quantity_grams: grams, source: "manual", **food.macros_for(grams)
    )
  end
end
