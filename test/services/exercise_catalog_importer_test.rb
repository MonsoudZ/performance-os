require "test_helper"

class ExerciseCatalogImporterTest < ActiveSupport::TestCase
  test "imports the canonical catalog idempotently" do
    importer = ExerciseCatalogImporter.new
    catalog_size = YAML.safe_load_file(ExerciseCatalogImporter::CATALOG_PATH).size

    assert_difference "Exercise.where(user_id: nil).count", catalog_size do
      assert_equal catalog_size, importer.call
    end

    assert_no_difference [ "Exercise.count", "ExerciseMuscleContribution.count", "MuscleGroup.count" ] do
      assert_equal catalog_size, importer.call
    end

    squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    assert_equal "barbell", squat.modality
    assert squat.is_compound?
    assert_equal %w[glutes quads], squat.muscle_groups.order(:name).pluck(:name)
  end
end
