class WeightTrend < ApplicationRecord
  self.primary_key = nil

  belongs_to :user

  validates :trend_date, presence: true, uniqueness: { scope: :user_id }
  validates :ewma_kg, numericality: { greater_than: 0 }
end
