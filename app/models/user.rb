class User < ApplicationRecord
  EXPERIENCE_LEVELS = %w[beginner intermediate advanced].freeze
  SEXES = %w[male female unspecified].freeze
  EQUIPMENT_OPTIONS = Exercise::MODALITIES

  has_secure_password

  # Two days is long enough for an address that batches or greylists, short
  # enough that a link found in an old inbox is dead.
  EMAIL_VERIFICATION_PERIOD = 2.days
  EMAIL_CHANGE_PERIOD = 2.days

  # How many accounts one mailbox may hold. A shared household address covering a
  # couple or a small family is a real thing; a fourth account on the same inbox
  # is somebody multiplying, and the AI coach is the thing worth multiplying for.
  # Counted against the canonical mailbox, so `me+1@` and `me+2@` are one.
  ACCOUNTS_PER_MAILBOX = 3

  # Both tokens carry the address they were issued for, so neither can confirm
  # an address it was not issued for, and both die the moment the thing they
  # describe moves — a confirmation once the account is verified, a change once
  # the request is confirmed or cancelled.
  generates_token_for :email_verification, expires_in: EMAIL_VERIFICATION_PERIOD do
    [ email_address, verified_at&.to_i ]
  end

  generates_token_for :email_change, expires_in: EMAIL_CHANGE_PERIOD do
    pending_email_address
  end

  # Order is load-bearing: `user.destroy` runs these in declaration order, and
  # several of them reference each other, so anything that points at another row
  # has to be listed before the row it points at. AccountDeletion is the only
  # caller and lifts the two guards this order cannot — see it before reordering.
  has_many :sessions, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :coach_narratives, dependent: :destroy
  has_many :coaching_decisions, dependent: :destroy
  has_many :conditioning_sessions, dependent: :destroy      # -> wearable_samples
  has_many :wearable_samples, dependent: :destroy           # -> wearable_devices
  has_many :wearable_devices, dependent: :destroy
  has_many :workout_sessions, dependent: :destroy           # -> workout_templates, exercises
  has_many :workout_templates, dependent: :destroy          # -> exercises
  has_many :exercise_prescriptions, dependent: :destroy     # -> exercises
  has_many :exercises, dependent: :destroy
  has_many :food_log_entries, dependent: :destroy           # -> foods
  has_many :foods, dependent: :destroy
  has_many :goal_periods, dependent: :destroy
  has_many :daily_readiness_inputs, dependent: :destroy
  has_many :readiness_scores, dependent: :destroy
  has_many :body_metrics, dependent: :destroy
  has_many :weight_trends, dependent: :destroy
  has_many :expenditure_estimates, dependent: :destroy
  has_many :mesocycles, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  # Normalized the same way, or "Me@Example.com " would be compared against a
  # stored address it is equal to and treated as a different one.
  normalizes :pending_email_address, with: ->(e) { e&.strip&.downcase.presence }
  # The profile's sex select offers "Prefer not to say", which posts an empty
  # string. The column's check constraint accepts NULL but not "", so without
  # this the whole profile save fails at the database — taking every other field
  # on the form down with it.
  normalizes :sex, with: ->(value) { value.presence }

  validates :email_address, presence: true, uniqueness: true
  validate :mailbox_under_capacity, if: :email_address_changed?
  validates :unit_system, inclusion: { in: %w[metric imperial] }
  validates :experience_level, inclusion: { in: EXPERIENCE_LEVELS }
  validates :sex, inclusion: { in: SEXES }, allow_nil: true
  validates :training_days_per_week,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 7 }
  validates :available_equipment, presence: true
  validate :recognized_time_zone
  validate :recognized_equipment

  before_validation :normalize_equipment
  before_validation :set_canonical_email_address

  def verified?
    verified_at.present?
  end

  def verify!
    update!(verified_at: Time.current) unless verified?
  end

  def email_change_pending?
    pending_email_address.present?
  end

  def self.mailbox_full?(address, except: nil)
    canonical = EmailAddress.canonical(address)
    return false if canonical.blank?

    scope = where(canonical_email_address: canonical)
    scope = scope.where.not(id: except.id) if except&.persisted?
    scope.count >= ACCOUNTS_PER_MAILBOX
  end

  def active_goal
    goal_periods.active_on(local_date).order(started_on: :desc).first
  end

  def imperial?
    Units.imperial?(unit_system)
  end

  def weight_unit
    Units.weight_unit(unit_system)
  end

  def length_unit
    Units.length_unit(unit_system)
  end

  def local_time
    Time.current.in_time_zone(time_zone)
  end

  def local_date
    Time.current.in_time_zone(time_zone).to_date
  end

  def local_date_at(time)
    time.in_time_zone(time_zone).to_date
  end

  def local_day_range(date)
    zone = ActiveSupport::TimeZone[time_zone]
    zone.local(date.year, date.month, date.day).all_day
  end

  private

  def set_canonical_email_address
    self.canonical_email_address = EmailAddress.canonical(email_address)
  end

  # Covers both ways an address gets into a mailbox — a new account and a
  # confirmed change — because validating only the first leaves the second as
  # the way around it.
  def mailbox_under_capacity
    return if email_address.blank?
    return unless User.mailbox_full?(email_address, except: self)

    errors.add(:email_address, "already has as many accounts as it can hold")
  end

  def normalize_equipment
    return if available_equipment.nil?

    self.available_equipment = available_equipment.compact_blank.uniq
  end

  def recognized_time_zone
    errors.add(:time_zone, "is not recognized") unless ActiveSupport::TimeZone[time_zone]
  end

  def recognized_equipment
    return if available_equipment.blank?

    unknown = available_equipment - EQUIPMENT_OPTIONS
    errors.add(:available_equipment, "includes an unknown option") if unknown.any?
  end
end
