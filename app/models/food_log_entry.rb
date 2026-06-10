class FoodLogEntry < ApplicationRecord
  MEAL_TYPES = %w[breakfast lunch dinner snack].freeze

  belongs_to :user
  belongs_to :food, optional: true
  belongs_to :copied_from_entry,
    class_name: "FoodLogEntry",
    optional: true,
    inverse_of: :copied_entry
  has_one :copied_entry,
    class_name: "FoodLogEntry",
    foreign_key: :copied_from_entry_id,
    dependent: :nullify,
    inverse_of: :copied_from_entry

  validates :logged_at, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES }
  validates :quantity_grams, numericality: { greater_than: 0 }
  validates :kcal, :protein_g, :carb_g, :fat_g, numericality: { greater_than_or_equal_to: 0 }
  validate :copied_entry_belongs_to_same_user

  before_validation :infer_meal_type, if: -> { meal_type.blank? && logged_at.present? }

  scope :on_date, ->(date) { where(logged_at: date.all_day) }

  def self.meal_type_for(time)
    case time.hour
    when 5..10 then "breakfast"
    when 11..15 then "lunch"
    when 16..21 then "dinner"
    else "snack"
    end
  end

  def meal_label
    meal_type.humanize
  end

  def macros_for(quantity)
    return food.macros_for(quantity) if food

    ratio = quantity.to_d / quantity_grams
    {
      kcal: (kcal * ratio).round(1),
      protein_g: (protein_g * ratio).round(1),
      carb_g: (carb_g * ratio).round(1),
      fat_g: (fat_g * ratio).round(1)
    }
  end

  private

  def infer_meal_type
    self.meal_type = self.class.meal_type_for(logged_at)
  end

  def copied_entry_belongs_to_same_user
    return unless copied_from_entry && copied_from_entry.user_id != user_id

    errors.add(:copied_from_entry, "must belong to the same user")
  end
end
