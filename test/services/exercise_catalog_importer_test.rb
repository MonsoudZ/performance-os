require "test_helper"

class ExerciseCatalogImporterTest < ActiveSupport::TestCase
  test "imports the canonical catalog idempotently" do
    importer = ExerciseCatalogImporter.new

    assert_difference "Exercise.where(user_id: nil).count", 32 do
      assert_equal 32, importer.call
    end

    assert_no_difference [ "Exercise.count", "ExerciseMuscleContribution.count", "MuscleGroup.count" ] do
      assert_equal 32, importer.call
    end

    squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
    assert_equal "barbell", squat.modality
    assert squat.is_compound?
    assert_equal %w[glutes quads], squat.muscle_groups.order(:name).pluck(:name)
  end
end
