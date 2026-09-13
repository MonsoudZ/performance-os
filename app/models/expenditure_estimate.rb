class ExpenditureEstimate < ApplicationRecord
  # How the number was arrived at. "energy_balance" is intake measured against
  # what the user's weight did; "wearable_energy" is the device's own basal plus
  # active figures, used only while there is not yet enough of the former.
  BASES = %w[energy_balance wearable_energy].freeze

  belongs_to :user

  validates :estimate_date, presence: true, uniqueness: { scope: :user_id }
  validates :estimated_tdee, numericality: { greater_than: 0 }
  validates :confidence, inclusion: { in: %w[low moderate high] }
  validates :basis, inclusion: { in: BASES }
end
