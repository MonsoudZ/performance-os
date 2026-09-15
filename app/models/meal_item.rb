class MealItem < ApplicationRecord
  belongs_to :meal, inverse_of: :meal_items
  belongs_to :food

  validates :quantity_grams, numericality: { greater_than: 0 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :food_id, uniqueness: { scope: :meal_id }
  validate :food_available_to_user

  def macros = food.macros_for(quantity_grams)

  private

  def food_available_to_user
    return if meal.blank? || food.blank?
    return if food.user_id.nil? || food.user_id == meal.user_id

    errors.add(:food, "is not available to this user")
  end
end
