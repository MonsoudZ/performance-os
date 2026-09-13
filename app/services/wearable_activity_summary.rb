# What a device reported about a day's movement, for pages that show it back.
# Steps and energy are not materialized into records of their own — nothing else
# in the app produces them, so there is nothing for them to merge with — and this
# is how they are read.
class WearableActivitySummary
  Summary = Data.define(:steps, :active_energy_kcal, :basal_energy_kcal) do
    def any?
      steps.present? || active_energy_kcal.present? || basal_energy_kcal.present?
    end

    # Only meaningful once the device has reported both halves; active energy on
    # its own is not a day's expenditure.
    def total_energy_kcal
      return if active_energy_kcal.nil? || basal_energy_kcal.nil?

      active_energy_kcal + basal_energy_kcal
    end
  end

  def initialize(user, on:)
    @user = user
    @on = on
  end

  def call
    totals = user.wearable_samples
      .where(metric_type: WearableSample::DAILY_TOTAL_METRICS)
      .where(started_at: user.local_day_range(on))
      .group(:metric_type)
      .sum(:value)

    Summary.new(
      steps: totals["step_count"]&.round,
      active_energy_kcal: totals["active_energy_kcal"]&.round,
      basal_energy_kcal: totals["basal_energy_kcal"]&.round
    )
  end

  private

  attr_reader :user, :on
end
