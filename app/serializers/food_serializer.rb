# A food as the client needs it to offer a portion of it.
#
# Macros are per `serving_grams`, exactly as stored, so the client can scale
# them the same way `Food#macros_for` does. Nothing here is unit-system
# dependent — grams and kilocalories read the same to every user — so unlike a
# weight these cross the boundary needing no conversion at either end.
#
# `custom` says whether this row belongs to the user. The shared catalog
# (`user_id: nil`) is readable by everybody and editable by nobody, and a client
# offering an edit button needs to know which it is looking at.
class FoodSerializer
  def initialize(food)
    @food = food
  end

  def as_json(*)
    {
      id: food.id,
      name: food.name,
      brand: food.brand,
      display_name: food.display_name,
      serving_grams: food.serving_grams.to_f,
      kcal: food.kcal.to_f,
      protein_g: food.protein_g.to_f,
      carb_g: food.carb_g.to_f,
      fat_g: food.fat_g.to_f,
      source: food.source,
      custom: food.user_id.present?
    }
  end

  private

  attr_reader :food
end
