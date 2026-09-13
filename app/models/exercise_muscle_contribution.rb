# A join row keyed by the pair it joins — exercise_muscle_contributions has no
# primary key (id: false), so a loaded row cannot be written back through save!,
# update! or destroy: Active Record builds those around the primary key and emits
# `WHERE "" IS NULL`, which Postgres rejects outright. Reach rows through the
# (exercise_id, muscle_group_id) unique index with update_all/delete_all instead,
# the way ExerciseCatalogImporter and WeightTrendMaterializer do.
class ExerciseMuscleContribution < ApplicationRecord
  belongs_to :exercise
  belongs_to :muscle_group

  validates :role, inclusion: { in: %w[primary secondary] }
  validates :fraction, numericality: { greater_than: 0, less_than_or_equal_to: 1 }
end
