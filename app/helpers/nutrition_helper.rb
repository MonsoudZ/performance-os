module NutritionHelper
  # An expenditure estimate is a number two very different methods can produce,
  # and which one produced it is most of what a reader needs to know about how
  # much to trust it.
  EXPENDITURE_BASIS_NOTES = {
    "energy_balance" => "measured from what you ate against what your weight actually did.",
    "wearable_energy" => "taken from your watch's own resting and active energy, " \
      "until a week of intake and weight-trend evidence can measure it instead."
  }.freeze

  def expenditure_basis_note(expenditure)
    EXPENDITURE_BASIS_NOTES[expenditure.basis]
  end
end
