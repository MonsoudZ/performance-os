# Turns a meal somebody has already logged into one they can log again.
#
# The same move as saving a workout from a session: what you ate, and how much,
# is already recorded, so keeping it should cost a name rather than re-entering
# every food.
class MealFromLoggedEntries
  def initialize(user, entries, name: nil)
    @user = user
    @entries = entries
    @name = name.to_s.strip.presence || self.class.suggested_name(user, entries)
  end

  # Prefilled so the field works untouched, and stepped around a name already in
  # use because saving breakfast on two different days is the ordinary case.
  def self.suggested_name(user, entries)
    base = entries.first&.meal_label.presence || "Meal"
    taken = user.meals.pluck(:name)
    return base unless taken.include?(base)

    (2..).each { |suffix| return "#{base} #{suffix}" unless taken.include?("#{base} #{suffix}") }
  end

  def call
    meal = user.meals.new(name: name)

    # One line per food: eating the same thing twice in a sitting is one portion
    # of it, not two rows that would collide on the meal's unique index.
    portions.each_with_index do |(food_id, grams), index|
      meal.meal_items.build(food_id: food_id, quantity_grams: grams, position: index + 1)
    end

    meal.save
    meal
  end

  private

  attr_reader :user, :entries, :name

  def portions
    entries
      .reject { |entry| entry.food_id.nil? }
      .group_by(&:food_id)
      .transform_values { |grouped| grouped.sum { |entry| entry.quantity_grams.to_d } }
  end
end
