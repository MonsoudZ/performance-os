class Food < ApplicationRecord
  belongs_to :user, optional: true
  has_many :food_log_entries, dependent: :nullify

  validates :name, presence: true
  validates :serving_grams, numericality: { greater_than: 0 }
  validates :kcal, :protein_g, :carb_g, :fat_g, numericality: { greater_than_or_equal_to: 0 }
  validates :source, inclusion: { in: %w[manual barcode import verified] }

  scope :available_to, ->(user) { where(user_id: [ nil, user.id ]).order(:name, :brand) }

  def macros_for(quantity_grams)
    ratio = quantity_grams.to_d / serving_grams
    {
      kcal: (kcal * ratio).round(1),
      protein_g: (protein_g * ratio).round(1),
      carb_g: (carb_g * ratio).round(1),
      fat_g: (fat_g * ratio).round(1)
    }
  end

  def display_name
    [ brand, name ].compact_blank.join(" · ")
  end
end
