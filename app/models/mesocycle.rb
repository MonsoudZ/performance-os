class Mesocycle < ApplicationRecord
  MAX_SET_BONUS = 3 # cap the accumulation volume ramp

  belongs_to :user

  validates :started_on, presence: true
  validates :weeks, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 16 }
  validates :deload_week, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :deload_within_block
  validate :ends_after_start

  scope :active, -> { where(ended_on: nil) }
  scope :active_on, ->(date) {
    where("started_on <= ?", date)
      .where("COALESCE(ended_on, started_on + (weeks * 7 - 1)) >= ?", date)
  }

  def natural_end
    started_on + (weeks * 7 - 1)
  end

  def effective_end
    ended_on || natural_end
  end

  # 1-based week index for a date inside the block.
  def current_week(date)
    [ ((date - started_on).to_i / 7) + 1, weeks ].min
  end

  def deload?(date)
    deload_week.present? && current_week(date) == deload_week
  end

  def phase(date)
    deload?(date) ? "deload" : "accumulation"
  end

  # Extra working sets to add during accumulation: +1 per week, bounded, and
  # zero on the deload week.
  def accumulation_set_bonus(date)
    return 0 if deload?(date)

    [ current_week(date) - 1, MAX_SET_BONUS ].min
  end

  def label
    name.presence || "#{weeks}-week block"
  end

  private

  def deload_within_block
    return if deload_week.blank? || weeks.blank?

    errors.add(:deload_week, "must be within the block length") if deload_week > weeks
  end

  def ends_after_start
    return if ended_on.blank? || started_on.blank? || ended_on >= started_on

    errors.add(:ended_on, "must be on or after the start date")
  end
end
