# Exercise in, "what is this lift being asked to do on this date" out.
#
# `TrainingTargets` answers that for a prescription; this puts the prescription
# lookup in front of it so a caller holding exercises — a workout template, a
# serializer — does not have to. Prescriptions are loaded once rather than per
# lift, because the caller is usually iterating.
#
# `nil` means no active target, which is not nothing: the progression engine
# skips that lift entirely. See TrainingTargetCoverage for where that is said
# out loud.
class ResolvedTrainingTargets
  def initialize(user, on: user.local_date)
    @user = user
    @on = on
  end

  def for(exercise)
    prescription = prescriptions[exercise.id]
    return unless prescription

    training_targets.targets_for(prescription)
  end

  private

  attr_reader :user, :on

  def training_targets
    @training_targets ||= TrainingTargets.new(user, on: on)
  end

  def prescriptions
    @prescriptions ||= user.exercise_prescriptions
      .active_on(on)
      .order(:started_on)
      .index_by(&:exercise_id)
  end
end
