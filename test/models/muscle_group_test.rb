require "test_helper"

class MuscleGroupTest < ActiveSupport::TestCase
  test "volume landmarks are ordered, because the status rule reads them as a scale" do
    MuscleGroup::LANDMARKS.each do |muscle, landmark|
      assert landmark[:mev] <= landmark[:mav],
        "#{muscle}: the adaptive target cannot sit below the minimum effective dose"
      assert landmark[:mav] <= landmark[:mrv],
        "#{muscle}: the adaptive target cannot sit above what is recoverable"
    end
  end

  test "every muscle the catalog actually trains has landmarks" do
    ExerciseCatalogImporter.new.call
    trained = MuscleGroup.joins(:exercise_muscle_contributions).distinct.pluck(:name)

    assert_predicate trained, :any?
    untracked = trained - MuscleGroup::LANDMARKS.keys
    # A muscle with no landmark still renders — WeeklyMuscleVolume calls it
    # "untracked" — so this fails quietly on the progress page rather than loudly.
    assert_empty untracked, "these muscles are trained by catalog lifts but get no volume guidance"
  end

  test "a muscle nothing has landmarks for says so rather than guessing" do
    group = MuscleGroup.create!(name: "zzz_forearms")

    assert_nil group.landmark
  end

  test "muscle names are unique in the database, not just in the model" do
    MuscleGroup.create!(name: "zzz_unique_check")

    duplicate = MuscleGroup.new(name: "zzz_unique_check")

    # Skipping the validation is the point: the index is what holds when two
    # importers race, and the validation cannot see the other transaction.
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end
end
