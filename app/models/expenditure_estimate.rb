class ExpenditureEstimate < ApplicationRecord
  self.primary_key = nil

  belongs_to :user

  validates :estimate_date, presence: true, uniqueness: { scope: :user_id }
  validates :estimated_tdee, numericality: { greater_than: 0 }
  validates :confidence, inclusion: { in: %w[low moderate high] }
end
