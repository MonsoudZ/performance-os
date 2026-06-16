# Builds a starting training program from the user's active goal: selects a
# balanced set of catalog lifts covering the major muscle groups, and writes an
# ExercisePrescription for each with rep/RIR/set targets matched to the goal.
# From there the existing engine takes over — the daily check-in modulates
# intensity, the double-progression evaluator reads logged sets to pick the next
# weight, and editing a target supersedes it. Idempotent and non-destructive:
# it only adds lifts the user isn't already training, so re-running fills gaps
# without clobbering manual targets.
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

  Result = Struct.new(:created, :focus, :goal, keyword_init: true) do
    def created_any? = created.any?
  end

  def initialize(user, effective_on: nil)
    @user = user
    @effective_on = effective_on || user.local_date
  end

  def call
    goal = user.active_goal
    return Result.new(created: [], focus: nil, goal: nil) unless goal

    focus = FOCUS_BY_GOAL.fetch(goal.goal_type, DEFAULT_FOCUS)
    scheme = Mesocycle::SCHEMES.fetch(focus)
    created = []

    ApplicationRecord.transaction do
      ensure_starting_block(focus)
      selected_exercises.each do |exercise|
        next if already_training?(exercise)

        created << create_prescription(exercise, scheme)
      end
    end

    Result.new(created: created, focus: focus, goal: goal)
  end

  private

  attr_reader :user, :effective_on

  # One lift per covered muscle group, de-duplicated (a lift primary for two
  # groups, e.g. a deadlift, is only prescribed once).
  def selected_exercises
    @selected_exercises ||= MUSCLE_COVERAGE.each_with_object([]) do |muscle, chosen|
      pick = candidates_for(muscle).find { |exercise| chosen.exclude?(exercise) }
      chosen << pick if pick
    end
  end

  def candidates_for(muscle)
    Exercise.available_to(user)
      .joins(exercise_muscle_contributions: :muscle_group)
      .where(exercise_muscle_contributions: { role: "primary" }, muscle_groups: { name: muscle })
      .sort_by { |exercise| [ exercise.is_compound? ? 0 : 1, MODALITY_RANK.fetch(exercise.modality, 9), exercise.name ] }
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
      working_sets: variant[:sets],
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
