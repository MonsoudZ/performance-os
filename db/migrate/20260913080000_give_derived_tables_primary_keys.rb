class GiveDerivedTablesPrimaryKeys < ActiveRecord::Migration[8.1]
  # These four tables were created with `id: false` because each row is derived
  # state addressed by a natural key — one per user per day, one per
  # exercise/muscle pair — and an id looked like dead weight.
  #
  # It cost more than it saved. Active Record builds every UPDATE and DELETE for
  # a loaded record around the primary key, so with none it emits
  # `WHERE "" IS NULL`, which Postgres rejects outright: save!, update!, destroy
  # and dependent: :destroy all fail, and only on the *second* write for a given
  # key, so the failure ships looking fine. That was four live bugs between
  # ExpenditureEstimator, the catalog importer, and deleting an exercise or a
  # muscle group.
  #
  # The natural keys stay exactly as they were — the unique indexes are what
  # actually enforce "one per user per day", and nothing about them changes.
  TABLES = %i[
    readiness_scores
    weight_trends
    expenditure_estimates
    exercise_muscle_contributions
  ].freeze

  def up
    TABLES.each { |table| add_column table, :id, :primary_key }
  end

  def down
    TABLES.each { |table| remove_column table, :id }
  end
end
