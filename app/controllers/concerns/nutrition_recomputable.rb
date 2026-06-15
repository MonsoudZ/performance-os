module NutritionRecomputable
  extend ActiveSupport::Concern

  private

  # Recompose the day's nutrition targets after a change that feeds them: a
  # goal change, or a logged/edited/removed food entry. Backdated logs pass
  # their own date; everything else defaults to today.
  def recompute_nutrition(date = Current.user.local_date)
    NutritionRecomputeJob.perform_later(Current.user, date)
  end
end
