module ExercisesHelper
  # Primary muscles first, then secondary — the order a lifter would name them.
  def exercise_muscles(exercise)
    exercise.exercise_muscle_contributions
      .sort_by { |contribution| [ contribution.role == "primary" ? 0 : 1, contribution.muscle_group.name ] }
  end

  def exercise_muscle_summary(exercise)
    names = exercise_muscles(exercise).map { |contribution| contribution.muscle_group.name.humanize }
    return "Unmapped" if names.empty?

    names.to_sentence
  end

  def exercise_catalog_label(exercise)
    exercise.user_id.nil? ? "Catalog" : "Custom"
  end

  # How the exercise is measured. `default_unit` is stored canonically, so a
  # weight-loaded lift reads "kg" in the column and "lb" to an imperial user;
  # reps, seconds and metres mean the same thing to everyone.
  def exercise_unit_label(exercise)
    exercise.default_unit == "kg" ? weight_unit : exercise.default_unit
  end

  # "100 kg × 8" style summary of one logged set, in the reader's units.
  def set_summary(set)
    return "#{set.reps} reps" if set.weight_kg.blank?

    "#{weight(set.weight_kg)} × #{set.reps}"
  end

  def decision_status_label(status)
    {
      "increase" => "Load increased",
      "hold" => "Held the load",
      "deload" => "Deloaded after a stall",
      "insufficient" => "Not enough sets to judge"
    }.fetch(status, status.to_s.humanize)
  end
end
