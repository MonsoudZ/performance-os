# A saved meal, and what one tap of it would log.
#
# The totals are computed from the foods rather than stored on the meal, so a
# food whose numbers were corrected corrects every meal built on it instead of
# leaving a stale copy behind. That is `Meal#totals` doing the work; this only
# rounds it for the wire.
class MealSerializer
  def initialize(meal)
    @meal = meal
  end

  def as_json(*)
    {
      id: meal.id,
      name: meal.name,
      items: meal.meal_items.map { |item| item_json(item) },
      totals: meal.totals.transform_keys(&:to_s).transform_values { |value| value.to_f.round(1) }
    }
  end

  private

  attr_reader :meal

  def item_json(item)
    {
      id: item.id,
      position: item.position,
      quantity_grams: item.quantity_grams.to_f,
      food: FoodSerializer.new(item.food).as_json
    }
  end
end
