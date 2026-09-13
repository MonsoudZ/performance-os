require "test_helper"

class ExerciseMuscleContributionTest < ActiveSupport::TestCase
  setup do
    @exercise = Exercise.create!(name: "Zzz Contribution Squat", modality: "barbell")
    @muscle = MuscleGroup.find_or_create_by!(name: "quads")
  end

  test "a fraction outside 0-1 is rejected by the model and by the database" do
    assert_not contribution(fraction: 0).valid?
    assert_not contribution(fraction: 1.5).valid?

    assert_raises(ActiveRecord::StatementInvalid) { contribution(fraction: 2).save(validate: false) }
  end

  test "a role the volume rule cannot price is rejected" do
    assert_not contribution(role: "stabilizer").valid?
    assert_raises(ActiveRecord::StatementInvalid) { contribution(role: "stabilizer").save(validate: false) }
  end

  test "one contribution per exercise and muscle, enforced by the index" do
    contribution.save!
    duplicate = contribution(fraction: 0.5, role: "secondary")

    # Two rows for the same pair would double-count that muscle's weekly volume.
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "deleting an exercise takes its contributions without instantiating them" do
    contribution.save!

    # dependent: :destroy would load each row and fail on the missing primary key.
    assert_difference "ExerciseMuscleContribution.count", -1 do
      @exercise.destroy!
    end
  end

  test "deleting a muscle group takes its contributions too" do
    muscle = MuscleGroup.create!(name: "zzz_forearms")
    @exercise.exercise_muscle_contributions.create!(muscle_group: muscle, role: "secondary", fraction: 0.5)

    assert_difference "ExerciseMuscleContribution.count", -1 do
      muscle.destroy!
    end
  end

  private

  def contribution(role: "primary", fraction: 1.0)
    @exercise.exercise_muscle_contributions.new(muscle_group: @muscle, role: role, fraction: fraction)
  end
end
