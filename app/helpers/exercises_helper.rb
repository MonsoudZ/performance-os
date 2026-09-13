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

  # "3 × 8 @ 100 kg" style summary of one logged set.
  def set_summary(set)
    return "#{set.reps} reps" if set.weight_kg.blank?

    weight = number_with_precision(set.weight_kg, precision: 2, strip_insignificant_zeros: true)
    "#{weight} kg × #{set.reps}"
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
