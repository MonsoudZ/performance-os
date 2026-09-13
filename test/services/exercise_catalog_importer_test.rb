require "test_helper"

class ExerciseCatalogImporterTest < ActiveSupport::TestCase
  test "imports the canonical catalog idempotently" do
    importer = ExerciseCatalogImporter.new
    catalog = YAML.safe_load_file(ExerciseCatalogImporter::CATALOG_PATH)

    assert_equal catalog.size, importer.call

    # Asserted on presence rather than on a count delta: catalog rows survive a
    # seed, so a test database that has already been seeded starts with them.
    imported = Exercise.where(user_id: nil).pluck(:name)
    assert_empty catalog.map { |entry| entry["name"] } - imported

    assert_no_difference [ "Exercise.count", "ExerciseMuscleContribution.count", "MuscleGroup.count" ] do
      assert_equal catalog.size, importer.call
    end

    squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    assert_equal "barbell", squat.modality
    assert squat.is_compound?
    assert_equal %w[glutes quads], squat.muscle_groups.order(:name).pluck(:name)
  end

  test "re-importing an exercise whose muscles changed updates it instead of raising" do
    ExerciseCatalogImporter.new.call
    squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    glutes = MuscleGroup.find_by!(name: "glutes")
    # Pretend the catalog previously called this secondary, as an edit to
    # db/catalog/exercises.yml would leave a live database.
    squat.exercise_muscle_contributions
      .where(muscle_group: glutes)
      .update_all(role: "secondary", fraction: 0.5)

    ExerciseCatalogImporter.new.call

    contribution = squat.exercise_muscle_contributions.find_by!(muscle_group: glutes)
    assert_equal "secondary", contribution.role
    assert_equal BigDecimal("0.5"), contribution.fraction
  end

  test "a muscle dropped from the catalog stops counting towards weekly volume" do
    ExerciseCatalogImporter.new.call
    squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    stray = MuscleGroup.create!(name: "zzz_stray_muscle")
    squat.exercise_muscle_contributions.create!(muscle_group: stray, role: "secondary", fraction: 0.5)

    ExerciseCatalogImporter.new.call

    # destroy_all here used to raise: the rows have no primary key to destroy by.
    assert_not_includes squat.reload.muscle_groups.pluck(:name), "zzz_stray_muscle"
  end
end
