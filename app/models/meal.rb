class Meal < ApplicationRecord
  include OrderedItems

  # The order the foods read in, from the order the editor's rows arrive in.
  ordered_by_position :meal_items

  belongs_to :user
  has_many :meal_items, -> { order(:position) }, dependent: :destroy, inverse_of: :meal
  has_many :foods, through: :meal_items

  accepts_nested_attributes_for :meal_items, allow_destroy: true, reject_if: :all_blank

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validate :has_items
  validate :foods_are_distinct

  # Macros are computed from the foods rather than stored, so correcting a
  # food's numbers corrects every meal built on it instead of leaving a stale
  # copy behind.
  def totals
    meal_items.each_with_object(Hash.new(0.to_d)) do |item, totals|
      item.macros.each { |nutrient, value| totals[nutrient] += value }
    end
  end

  def kcal = totals[:kcal]

  def protein_g = totals[:protein_g]

  private

  def has_items
    return if meal_items.reject(&:marked_for_destruction?).any?

    errors.add(:meal_items, "must include at least one food")
  end

  # `MealItem` validates this too, but only against rows already in the table:
  # two new items naming the same food both pass and then collide on the unique
  # index, which reached the user as a 500 from the editor rather than as a
  # sentence about their form. The invariant is the meal's — it is about the set
  # of items, not about any one of them — so the meal is where it is checked.
  #
  # Combining rather than repeating is also what a meal means: eating oats twice
  # in one sitting is one portion of oats, which is exactly what
  # `MealFromLoggedEntries` does when it builds a meal out of a logged day.
  def foods_are_distinct
    food_ids = meal_items.reject(&:marked_for_destruction?).filter_map(&:food_id)
    return if food_ids.uniq.length == food_ids.length

    errors.add(:meal_items, "must not list the same food twice — combine the portions instead")
  end
end
