# One logged thing eaten.
#
# The macros are the entry's own, not the food's: a logged entry snapshots what
# was eaten, so correcting a food's numbers afterwards leaves the record of
# yesterday's breakfast alone. `food` can be null — deleting a custom food
# nullifies the link rather than erasing the meals it was part of.
#
# `source` distinguishes an entry typed in from one that arrived as a meal or a
# copy of yesterday, so the day's evidence does not pretend four entries were
# tapped in one at a time.
class FoodLogEntrySerializer
  def initialize(entry)
    @entry = entry
  end

  def as_json(*)
    {
      id: entry.id,
      logged_at: entry.logged_at.iso8601,
      meal_type: entry.meal_type,
      quantity_grams: entry.quantity_grams.to_f,
      kcal: entry.kcal.to_f,
      protein_g: entry.protein_g.to_f,
      carb_g: entry.carb_g.to_f,
      fat_g: entry.fat_g.to_f,
      source: entry.source,
      food: entry.food && FoodSerializer.new(entry.food).as_json
    }
  end

  private

  attr_reader :entry
end
