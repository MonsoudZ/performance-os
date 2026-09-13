# The rep range, effort target and set count in force for a lift on a given day.
#
# A training block owns its scheme. It used to be *applied* — a button rewrote
# every active target to the focus's preset, superseding each one — which meant
# starting a block did nothing until you remembered to press it, ending a block
# left its scheme behind forever, and a rep range you had chosen by hand was gone
# the first time you pressed it. Targets are composed here instead, so a block
# change recomposes the plan the way every other input does.
#
# What the block owns is the *scheme*: reps, RIR and the baseline set count.
# Today's volume on top of that — the accumulation ramp, a deload or recovery
# cut — stays with `DailyTrainingOrchestrator`, which is the thing that knows
# about today. And a prescription that opts out with `follows_block_scheme:
# false` keeps its own scheme while still sitting inside the block: opting out
# says "this rep range is mine", not "ignore the block".
class TrainingTargets
  Targets = Data.define(
    :rep_min, :rep_max, :target_rir_min, :target_rir_max, :working_sets, :source
  ) do
    def from_block?
      source == "block_scheme"
    end

    def label
      "#{working_sets} × #{rep_min}–#{rep_max} @ #{rir_amount(target_rir_min)}–#{rir_amount(target_rir_max)} RIR"
    end

    private

    def rir_amount(value)
      value.to_f.round(1)
    end
  end

  def initialize(user, on:)
    @user = user
    @on = on
  end

  # The block in force on this date, or nil. Loaded once: callers resolve targets
  # for every lift in a plan.
  def mesocycle
    return @mesocycle if defined?(@mesocycle)

    @mesocycle = user.mesocycles.active_on(on).order(started_on: :desc).first
  end

  def targets_for(prescription)
    variant = block_variant_for(prescription)
    return baseline(prescription) if variant.nil?

    build(
      rep_min: variant[:rep_min],
      rep_max: variant[:rep_max],
      target_rir_min: variant[:rir_min],
      target_rir_max: variant[:rir_max],
      working_sets: variant[:sets],
      source: "block_scheme"
    )
  end

  private

  attr_reader :user, :on

  # Compounds run heavier and lower-rep than isolations, so a focus carries a
  # variant for each.
  def block_variant_for(prescription)
    return unless mesocycle && prescription.follows_block_scheme?

    scheme = mesocycle.scheme
    prescription.exercise.is_compound? ? scheme[:compound] : scheme[:isolation]
  end

  def baseline(prescription)
    build(
      rep_min: prescription.rep_min,
      rep_max: prescription.rep_max,
      target_rir_min: prescription.target_rir_min,
      target_rir_max: prescription.target_rir_max,
      working_sets: prescription.working_sets,
      source: "prescription"
    )
  end

  # Normalized on the way out so a caller never has to know whether a number came
  # from a preset hash or a decimal column — the progression engine compares
  # these against logged sets and snapshots them into an immutable decision.
  def build(rep_min:, rep_max:, target_rir_min:, target_rir_max:, working_sets:, source:)
    Targets.new(
      rep_min: rep_min.to_i,
      rep_max: rep_max.to_i,
      target_rir_min: BigDecimal(target_rir_min.to_s),
      target_rir_max: BigDecimal(target_rir_max.to_s),
      working_sets: working_sets.to_i,
      source: source
    )
  end
end
