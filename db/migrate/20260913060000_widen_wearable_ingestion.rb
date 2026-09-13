class WidenWearableIngestion < ActiveRecord::Migration[8.1]
  # The metric types the check constraint allowed before this migration. Kept so
  # `down` restores exactly what was there rather than an approximation.
  # Spelled out rather than read from WearableSample::METRIC_UNITS: a migration
  # has to keep describing the change it made after the model moves on.
  PREVIOUS_METRIC_TYPES = %w[hrv_sdnn_ms resting_hr_bpm sleep_asleep].freeze
  METRIC_TYPES = PREVIOUS_METRIC_TYPES + %w[
    workout step_count active_energy_kcal basal_energy_kcal body_mass_kg
  ].freeze

  def up
    remove_check_constraint :wearable_samples, name: "wearable_samples_metric_type_check"
    add_check_constraint :wearable_samples, metric_type_constraint(METRIC_TYPES),
      name: "wearable_samples_metric_type_check"

    # A body-mass sample is a measurement, so it falls under the storage rule the
    # weight columns already follow: the stored scale has to exceed the displayed
    # one or a value changes under the user when it round-trips through pounds.
    # Three decimals were enough for milliseconds and minutes and are not enough
    # for kilograms.
    change_column :wearable_samples, :value, :decimal, precision: 14, scale: 6

    # A synced workout becomes a ConditioningSession. The link is what makes
    # re-materializing the same day idempotent, and it lets the session say where
    # it came from instead of looking hand-logged.
    add_reference :conditioning_sessions, :wearable_sample, null: true, foreign_key: true, index: false
    add_index :conditioning_sessions, :wearable_sample_id,
      unique: true, where: "wearable_sample_id IS NOT NULL",
      name: "index_conditioning_sessions_on_wearable_sample_id"

    # Two estimates of the same quantity arrived at different ways. Recording
    # which one produced a row is the difference between an auditable number and
    # a number.
    add_column :expenditure_estimates, :basis, :string, null: false, default: "energy_balance"
    add_check_constraint :expenditure_estimates,
      "basis IN ('energy_balance', 'wearable_energy')",
      name: "expenditure_estimates_basis_check"
  end

  def down
    remove_check_constraint :expenditure_estimates, name: "expenditure_estimates_basis_check"
    remove_column :expenditure_estimates, :basis

    remove_index :conditioning_sessions, name: "index_conditioning_sessions_on_wearable_sample_id"
    remove_reference :conditioning_sessions, :wearable_sample, foreign_key: true

    execute "DELETE FROM wearable_samples WHERE metric_type NOT IN (#{PREVIOUS_METRIC_TYPES.map { |type| connection.quote(type) }.join(', ')})"
    change_column :wearable_samples, :value, :decimal, precision: 10, scale: 3

    remove_check_constraint :wearable_samples, name: "wearable_samples_metric_type_check"
    add_check_constraint :wearable_samples, metric_type_constraint(PREVIOUS_METRIC_TYPES),
      name: "wearable_samples_metric_type_check"
  end

  private

  def metric_type_constraint(metric_types)
    "metric_type IN (#{metric_types.map { |type| connection.quote(type) }.join(', ')})"
  end
end
