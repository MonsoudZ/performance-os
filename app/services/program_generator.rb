# Builds a starting training program from the user's active goal: selects a
# balanced set of catalog lifts covering the major muscle groups, and writes an
# ExercisePrescription for each with rep/RIR/set targets matched to the goal.
# From there the existing engine takes over — the daily check-in modulates
# intensity, the double-progression evaluator reads logged sets to pick the next
# weight, and editing a target supersedes it. Idempotent and non-destructive:
# it only adds lifts the user isn't already training, so re-running fills gaps
# without clobbering manual targets. In `prune_unavailable` mode (a "refresh"),
# it also retires active lifts the user no longer has the equipment for, then
# adds the now-possible replacements.
class ProgramGenerator
  # Goal type -> block focus, which selects the rep/RIR/set scheme (and the
  # starting mesocycle) from Mesocycle::SCHEMES.
  FOCUS_BY_GOAL = {
    "build_muscle" => "hypertrophy",
    "lose_fat" => "hypertrophy",
    "longevity" => "hypertrophy",
    "marathon" => "hypertrophy",
    "increase_strength" => "strength",
    "athletic_performance" => "power",
    "vertical_jump" => "power"
  }.freeze
  DEFAULT_FOCUS = "hypertrophy"

  # Major muscle groups a balanced full-body starting program should cover, in
  # priority order. One primary lift is chosen per group.
  MUSCLE_COVERAGE = %w[
    quads back chest shoulders hamstrings glutes biceps triceps calves abs
  ].freeze

  # Prefer free-weight compounds when a group has several primary options.
  MODALITY_RANK = {
    "barbell" => 0, "dumbbell" => 1, "machine" => 2, "cable" => 3, "bodyweight" => 4, "other" => 5
  }.freeze

  DEFAULT_INCREMENT_KG = 2.5

  # Working-set adjustment by training experience.
  SET_DELTA_BY_EXPERIENCE = { "beginner" => -1, "intermediate" => 0, "advanced" => 1 }.freeze
  # Below this many training days, cover only the big compound-driven groups.
  LOW_FREQUENCY_DAYS = 2
  HIGH_FREQUENCY_DAYS = 5
  BIG_ROCK_COUNT = 6

  Result = Struct.new(:created, :retired, :focus, :goal, keyword_init: true) do
    def created_any? = created.any?
    def retired_any? = retired.any?
    def changed_any? = created_any? || retired_any?
  end

  def initialize(user, effective_on: nil, prune_unavailable: false)
    @user = user
    @effective_on = effective_on || user.local_date
    @prune_unavailable = prune_unavailable
  end

  def call
    goal = user.active_goal
    return Result.new(created: [], retired: [], focus: nil, goal: nil) unless goal

    focus = FOCUS_BY_GOAL.fetch(goal.goal_type, DEFAULT_FOCUS)
    scheme = Mesocycle::SCHEMES.fetch(focus)
    created = []
    retired = []

    ApplicationRecord.transaction do
      retired = prune_unavailable_lifts if prune_unavailable?
      ensure_starting_block(focus)
      selected_exercises.each do |exercise|
        next if already_training?(exercise)

        created << create_prescription(exercise, scheme)
      end
    end

    Result.new(created: created, retired: retired, focus: focus, goal: goal)
  end

  private

  attr_reader :user, :effective_on

  def prune_unavailable?
    @prune_unavailable
  end

  # Retire active lifts whose equipment the user no longer has. The add step
  # that follows then fills the freed muscle slots with available alternatives.
  def prune_unavailable_lifts
    user.exercise_prescriptions.active.includes(:exercise).reject do |prescription|
      user.available_equipment.include?(prescription.exercise.modality)
    end.each { |prescription| prescription.update!(ended_on: prescription.ended_on_for(effective_on)) }
  end

  # One lift per covered muscle group, de-duplicated (a lift primary for two
  # groups, e.g. a deadlift, is only prescribed once).
  def selected_exercises
    @selected_exercises ||= covered_muscles.each_with_object([]) do |muscle, chosen|
      pick = candidates_for(muscle).find { |exercise| chosen.exclude?(exercise) }
      chosen << pick if pick
    end
  end

  # Fewer training days → cover only the big compound-driven groups; more days
  # can carry the full set of accessories.
  def covered_muscles
    return MUSCLE_COVERAGE.first(BIG_ROCK_COUNT) if user.training_days_per_week <= LOW_FREQUENCY_DAYS

    MUSCLE_COVERAGE
  end

  # Only lifts the user has the equipment for (bodyweight included only if they
  # kept it). Free-weight compounds rank first within a group.
  def candidates_for(muscle)
    Exercise.available_to(user)
      .joins(exercise_muscle_contributions: :muscle_group)
      .where(exercise_muscle_contributions: { role: "primary" }, muscle_groups: { name: muscle })
      .select { |exercise| user.available_equipment.include?(exercise.modality) }
      .sort_by { |exercise| [ exercise.is_compound? ? 0 : 1, MODALITY_RANK.fetch(exercise.modality, 9), exercise.name ] }
  end

  # Experience sets the baseline volume; high training frequency adds a set.
  def set_delta
    delta = SET_DELTA_BY_EXPERIENCE.fetch(user.experience_level, 0)
    delta += 1 if user.training_days_per_week >= HIGH_FREQUENCY_DAYS
    delta
  end

  def already_training?(exercise)
    user.exercise_prescriptions.active.exists?(exercise_id: exercise.id)
  end

  def create_prescription(exercise, scheme)
    variant = exercise.is_compound? ? scheme[:compound] : scheme[:isolation]
    user.exercise_prescriptions.create!(
      exercise: exercise,
      rep_min: variant[:rep_min],
      rep_max: variant[:rep_max],
      target_rir_min: variant[:rir_min],
      target_rir_max: variant[:rir_max],
      working_sets: [ variant[:sets] + set_delta, 1 ].max,
      increment_kg: DEFAULT_INCREMENT_KG,
      progression_model: "double_progression",
      started_on: effective_on
    )
  end

  # Give the program a block so deload/accumulation logic has context. Only if
  # the user isn't already mid-block, so we never disrupt an active mesocycle.
  def ensure_starting_block(focus)
    return if user.mesocycles.active_on(effective_on).exists?

    user.mesocycles.create!(focus: focus, started_on: effective_on, weeks: 4, deload_week: 4)
  end
end
