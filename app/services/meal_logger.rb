# Logs every food in a meal at once.
#
# Macros are recomputed from each food rather than stored on the meal, so a food
# whose numbers were corrected corrects the meal too instead of leaving every
# copy stale. The entries themselves still snapshot their macros, because a
# logged entry is a record of what was eaten.
class MealLogger
  Result = Data.define(:entries, :meal) do
    def logged_any? = entries.any?
  end

  def initialize(meal, at: Time.current)
    @meal = meal
    @at = at
  end

  def call
    entries = ApplicationRecord.transaction do
      meal.meal_items.includes(:food).map do |item|
        meal.user.food_log_entries.create!(
          food: item.food,
          logged_at: at,
          # The meal it belongs to is the one happening now, like a one-tap food.
          meal_type: FoodLogEntry.meal_type_for(at),
          quantity_grams: item.quantity_grams,
          # Says where this came from, so the day's evidence does not pretend
          # four entries were typed one at a time.
          source: "meal",
          **item.food.macros_for(item.quantity_grams)
        )
      end
    end

    Result.new(entries: entries, meal: meal)
  end

  private

  attr_reader :meal, :at
end
