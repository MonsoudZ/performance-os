class ReadinessScore < ApplicationRecord
  self.primary_key = nil

  belongs_to :user

  validates :score_date, presence: true, uniqueness: { scope: :user_id }
  validates :score, inclusion: { in: 0..100 }
end
