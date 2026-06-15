class Mesocycle < ApplicationRecord
  FOCUSES = {
    "hypertrophy" => "Hypertrophy — chase volume and effort; reps and a strong pump over max load.",
    "strength" => "Strength — prioritize load and low reps; quality over quantity.",
    "power" => "Power — move lighter loads with maximum intent; keep volume low and crisp."
  }.freeze
  # How aggressively accumulation volume ramps, by focus.
  SET_BONUS_CAPS = { "hypertrophy" => 3, "strength" => 1, "power" => 1 }.freeze

  # Preset rep/RIR/set schemes per focus, split by exercise type (compounds run
  # heavier/lower-rep than isolations). Applied to a user's targets on request.
  SCHEMES = {
    "hypertrophy" => {
      compound: { rep_min: 6, rep_max: 10, rir_min: 1, rir_max: 2, sets: 3 },
      isolation: { rep_min: 10, rep_max: 15, rir_min: 0, rir_max: 1, sets: 3 }
    },
    "strength" => {
      compound: { rep_min: 3, rep_max: 5, rir_min: 2, rir_max: 3, sets: 4 },
      isolation: { rep_min: 6, rep_max: 8, rir_min: 1, rir_max: 2, sets: 3 }
    },
    "power" => {
      compound: { rep_min: 2, rep_max: 4, rir_min: 2, rir_max: 3, sets: 3 },
      isolation: { rep_min: 5, rep_max: 8, rir_min: 1, rir_max: 2, sets: 3 }
    }
  }.freeze

  include DateRanged

  belongs_to :user

  validates :weeks, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 16 }
  validates :focus, inclusion: { in: FOCUSES.keys }
  validates :deload_week, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :deload_within_block

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

  # Extra working sets to add during accumulation: +1 per week, capped by the
  # block focus, and zero on the deload week.
  def accumulation_set_bonus(date)
    return 0 if deload?(date)

    [ current_week(date) - 1, SET_BONUS_CAPS.fetch(focus, 3) ].min
  end

  def focus_emphasis
    FOCUSES.fetch(focus, FOCUSES["hypertrophy"])
  end

  def scheme
    SCHEMES.fetch(focus, SCHEMES["hypertrophy"])
  end

  def scheme_summary
    compound = scheme[:compound]
    isolation = scheme[:isolation]
    "Compounds #{compound[:rep_min]}–#{compound[:rep_max]} reps @ #{compound[:rir_min]}–#{compound[:rir_max]} RIR · " \
      "isolations #{isolation[:rep_min]}–#{isolation[:rep_max]} reps"
  end

  def label
    name.presence || "#{weeks}-week block"
  end

  private

  def deload_within_block
    return if deload_week.blank? || weeks.blank?

    errors.add(:deload_week, "must be within the block length") if deload_week > weeks
  end
end
