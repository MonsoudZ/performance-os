# Measurements were stored to two decimal places, which is finer than a
# kilogram scale reads but far coarser than the unit conversion needs. An
# imperial user who logged 45.25 lb had 20.53 kg stored, which reads back as
# 45.3 lb — their entry was silently changed, and re-saving the set persisted
# the changed value. Height in inches had the same problem.
#
# The scales below are not taste. For a value to survive typed -> stored ->
# displayed -> typed unchanged, the stored resolution has to be finer than the
# displayed resolution by enough to absorb the conversion. Measured against real
# entries (see the round-trip tests), pounds shown to four decimals need at least
# five decimals of kilograms and inches need four of centimetres; these take six
# and four for headroom. Widening a decimal column is metadata-only in
# PostgreSQL and every stored value stays valid.
class WidenMeasurementPrecision < ActiveRecord::Migration[8.1]
  WEIGHT = { precision: 10, scale: 6 }.freeze

  def up
    # The generated 1RM column reads weight_kg, so PostgreSQL will not let the
    # column change underneath it. Drop it, widen, then rebuild at matching scale.
    remove_column :set_entries, :estimated_1rm_kg
    change_column :set_entries, :weight_kg, :decimal, **WEIGHT
    add_estimated_1rm

    change_column :body_metrics, :weight_kg, :decimal, **WEIGHT
    change_column :body_metrics, :body_fat_pct, :decimal, precision: 5, scale: 2
    change_column :exercise_prescriptions, :increment_kg, :decimal, precision: 9, scale: 6, null: false
    change_column :weight_trends, :ewma_kg, :decimal, **WEIGHT.merge(null: false)
    change_column :weight_trends, :raw_kg, :decimal, **WEIGHT
    change_column :expenditure_estimates, :trend_weight_kg, :decimal, **WEIGHT
    change_column :users, :height_cm, :decimal, precision: 8, scale: 4
  end

  def down
    remove_column :set_entries, :estimated_1rm_kg
    change_column :set_entries, :weight_kg, :decimal, precision: 6, scale: 2
    add_estimated_1rm(precision: 7, scale: 2)

    change_column :body_metrics, :weight_kg, :decimal, precision: 6, scale: 2
    change_column :body_metrics, :body_fat_pct, :decimal, precision: 4, scale: 1
    change_column :exercise_prescriptions, :increment_kg, :decimal, precision: 5, scale: 2, null: false
    change_column :weight_trends, :ewma_kg, :decimal, precision: 6, scale: 2, null: false
    change_column :weight_trends, :raw_kg, :decimal, precision: 6, scale: 2
    change_column :expenditure_estimates, :trend_weight_kg, :decimal, precision: 6, scale: 2
    change_column :users, :height_cm, :decimal, precision: 5, scale: 1
  end

  private

  def add_estimated_1rm(precision: 12, scale: 6)
    add_column :set_entries, :estimated_1rm_kg, :virtual,
      type: :decimal,
      precision: precision,
      scale: scale,
      as: "weight_kg * (1 + reps::numeric / 30)",
      stored: true
  end
end
