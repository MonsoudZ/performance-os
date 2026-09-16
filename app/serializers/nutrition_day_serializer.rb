# A day of eating, as the nutrition page shows it.
#
# The numbers are read off the `daily_nutrition` decision rather than summed
# here, which is what the web page does too. The decision is the record of what
# the engine concluded and the numbers it concluded from; summing the entries
# separately would put a second, differently-derived total next to it that
# nobody could reconcile. It is written by the recompute job, so right after a
# log it is one job behind — the entries below are live, the verdict catches up,
# and the client can show both honestly. There is no decision at all until
# something recomputes the day, exactly as on the web.
#
# `current_meal_type` is which meal is happening now. One-tap logging files an
# entry under that rather than under whatever meal the food was last eaten at:
# carrying the old one over stamped an 8pm entry as breakfast, and this page
# groups by meal, so the record contradicted its own timestamp.
class NutritionDaySerializer
  def initialize(user, date:, entries:, decision:, frequent_foods:, meals:, yesterday_entry_count:)
    @user = user
    @date = date
    @entries = entries
    @decision = decision
    @frequent_foods = frequent_foods
    @meals = meals
    @yesterday_entry_count = yesterday_entry_count
  end

  def as_json(*)
    {
      date: date.iso8601,
      current_meal_type: FoodLogEntry.meal_type_for(user.local_time),
      # Flat, each carrying its own `meal_type`: grouping is the client's
      # display decision, and a flat list is what it has to re-sort anyway when
      # something is logged.
      entries: entries.map { |entry| FoodLogEntrySerializer.new(entry).as_json },
      decision: decision && DecisionSerializer.new(decision).as_json,
      frequent_foods: frequent_foods.map { |suggestion| suggestion_json(suggestion) },
      meals: meals.map { |meal| MealSerializer.new(meal).as_json },
      # Whether offering "copy yesterday" would do anything.
      yesterday_entry_count: yesterday_entry_count
    }
  end

  private

  attr_reader :user, :date, :entries, :decision, :frequent_foods, :meals, :yesterday_entry_count

  # The portion is the memory worth keeping — the quantity this food was last
  # logged at, so nobody retypes "80" every morning.
  def suggestion_json(suggestion)
    {
      food: FoodSerializer.new(suggestion.food).as_json,
      quantity_grams: suggestion.quantity_grams.to_f,
      kcal: suggestion.kcal.to_f,
      protein_g: suggestion.protein_g.to_f,
      times_logged: suggestion.times_logged
    }
  end
end
