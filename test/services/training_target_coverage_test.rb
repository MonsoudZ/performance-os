require "test_helper"

class TrainingTargetCoverageTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @squat = Exercise.find_or_create_by!(name: "Zzz Cover Squat") { |e| e.modality = "barbell" }
    @curl = Exercise.find_or_create_by!(name: "Zzz Cover Curl") { |e| e.modality = "dumbbell" }
    @template = build_template("Zzz Cover Lower", [ @squat, @curl ])
  end

  test "names the exercises no active target covers" do
    prescribe(@squat)

    assert_equal [ @curl ], coverage.uncovered_in(@template)
  end

  test "a fully covered workout reports nothing" do
    prescribe(@squat)
    prescribe(@curl)

    assert_empty coverage.uncovered_in(@template)
  end

  # A superseded target is not a target: DateRanged ends one rather than
  # mutating it, and an ended prescription is what the evaluator will not find.
  test "a target that has already ended does not count as cover" do
    prescribe(@squat, started_on: Date.current - 30, ended_on: Date.current - 1)

    assert_equal [ @squat, @curl ], coverage.uncovered_in(@template)
  end

  test "a target that starts later does not cover today" do
    prescribe(@squat, started_on: Date.current + 7)

    assert_includes coverage.uncovered_in(@template), @squat
  end

  test "the answer is given in the order the workout is performed" do
    template = build_template("Zzz Cover Order", [ @curl, @squat ])

    assert_equal [ @curl, @squat ], coverage.uncovered_in(template)
  end

  private

  def coverage
    TrainingTargetCoverage.new(@user)
  end

  def build_template(name, exercises)
    template = @user.workout_templates.new(name: name, weekdays: [ 1 ])
    exercises.each_with_index do |exercise, index|
      template.workout_template_exercises.build(exercise: exercise, position: index + 1)
    end
    template.save!
    template
  end

  def prescribe(exercise, started_on: Date.current - 7, ended_on: nil)
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: started_on, ended_on: ended_on
    )
  end
end
