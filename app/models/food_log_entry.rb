class FoodLogEntry < ApplicationRecord
  belongs_to :user
  belongs_to :food, optional: true

  validates :logged_at, presence: true
  validates :quantity_grams, numericality: { greater_than: 0 }
  validates :kcal, :protein_g, :carb_g, :fat_g, numericality: { greater_than_or_equal_to: 0 }

  scope :on_date, ->(date) { where(logged_at: date.all_day) }
end
