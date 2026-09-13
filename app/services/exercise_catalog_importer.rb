class ExerciseCatalogImporter
  CATALOG_PATH = Rails.root.join("db/catalog/exercises.yml")
  CONTRIBUTION_FRACTIONS = {
    "primary" => 1.0,
    "secondary" => 0.5
  }.freeze

  def initialize(path: CATALOG_PATH)
    @path = path
  end

  def call
    imported = 0

    Exercise.transaction do
      catalog_entries.each do |attributes|
        import_exercise(attributes)
        imported += 1
      end
    end

    imported
  end

  private

  attr_reader :path

  def catalog_entries
    YAML.safe_load_file(path).map(&:with_indifferent_access)
  end

  def import_exercise(attributes)
    exercise = Exercise.find_or_initialize_by(user_id: nil, name: attributes.fetch(:name))
    exercise.update!(
      modality: attributes.fetch(:modality),
      is_compound: attributes.fetch(:compound),
      default_unit: attributes.fetch(:default_unit, "kg")
    )

    sync_muscles(exercise, attributes.fetch(:muscles))
  end

  # Contributions are written through their (exercise_id, muscle_group_id) unique
  # index rather than through save!, because the table has no primary key — see
  # ExerciseMuscleContribution. Re-importing an exercise whose muscles changed in
  # the catalog used to raise here rather than update it, which only ever showed
  # up against a database that already had the old rows.
  def sync_muscles(exercise, muscles)
    muscle_names = muscles.keys
    exercise.exercise_muscle_contributions
      .where.not(muscle_group_id: MuscleGroup.where(name: muscle_names).select(:id))
      .delete_all

    muscles.each do |muscle_name, role|
      muscle_group = MuscleGroup.find_or_create_by!(name: muscle_name)
      write_contribution(exercise, muscle_group, role: role, fraction: CONTRIBUTION_FRACTIONS.fetch(role))
    end
  end

  def write_contribution(exercise, muscle_group, attributes)
    scope = exercise.exercise_muscle_contributions.where(muscle_group: muscle_group)
    existing = scope.take
    return exercise.exercise_muscle_contributions.create!(attributes.merge(muscle_group: muscle_group)) if existing.nil?

    # update_all skips validations, so run them against the loaded row first.
    existing.assign_attributes(attributes)
    existing.validate!
    scope.update_all(attributes)
    existing
  end
end
