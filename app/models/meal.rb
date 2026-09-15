class Meal < ApplicationRecord
  belongs_to :user
  has_many :meal_items, -> { order(:position) }, dependent: :destroy, inverse_of: :meal
  has_many :foods, through: :meal_items

  accepts_nested_attributes_for :meal_items, allow_destroy: true, reject_if: :all_blank

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validate :has_items

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
end
