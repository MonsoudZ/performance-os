module ApplicationHelper
  # What a lift's target actually is today, composed against the active training
  # block. Views must not read `rep_min`/`working_sets` off a prescription to
  # describe the present — those columns are the baseline the block may be
  # overriding. `ExercisePrescription#target_label` still describes the stored
  # record itself, which is what a *past* target should show.
  #
  # Memoized per request: a page renders one of these per lift, and they all
  # resolve against the same block.
  def todays_training_targets
    @todays_training_targets ||= TrainingTargets.new(Current.user, on: Current.user.local_date)
  end

  def training_targets_for(prescription)
    todays_training_targets.targets_for(prescription)
  end
end
