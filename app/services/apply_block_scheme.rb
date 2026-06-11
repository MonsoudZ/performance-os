# Rewrites a user's active training targets to a focus's preset rep/RIR/set
# scheme, using the compound variant for compound lifts and the isolation
# variant otherwise. Returns the number of targets updated.
class ApplyBlockScheme
  def initialize(user, focus:)
    @user = user
    @focus = focus
  end

  def call
    scheme = Mesocycle::SCHEMES[@focus]
    return 0 unless scheme

    updated = 0
    @user.exercise_prescriptions.active.includes(:exercise).find_each do |prescription|
      variant = prescription.exercise.is_compound? ? scheme[:compound] : scheme[:isolation]
      prescription.update!(
        rep_min: variant[:rep_min],
        rep_max: variant[:rep_max],
        target_rir_min: variant[:rir_min],
        target_rir_max: variant[:rir_max],
        working_sets: variant[:sets]
      )
      updated += 1
    end
    updated
  end
end
