class BodyMetric < ApplicationRecord
  belongs_to :user

  validates :measured_on, presence: true
  validates :weight_kg, numericality: { greater_than: 0 }, allow_nil: true
  validates :body_fat_pct, numericality: { in: 0..100 }, allow_nil: true
end
