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

  def sync_muscles(exercise, muscles)
    muscle_names = muscles.keys
    exercise.exercise_muscle_contributions
      .joins(:muscle_group)
      .where.not(muscle_groups: { name: muscle_names })
      .destroy_all

    muscles.each do |muscle_name, role|
      muscle_group = MuscleGroup.find_or_create_by!(name: muscle_name)
      contribution = exercise.exercise_muscle_contributions.find_or_initialize_by(muscle_group: muscle_group)
      contribution.update!(role: role, fraction: CONTRIBUTION_FRACTIONS.fetch(role))
    end
  end
end
