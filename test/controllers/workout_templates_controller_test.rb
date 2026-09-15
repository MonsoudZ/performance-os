require "test_helper"

class WorkoutTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @squat = Exercise.create!(name: "Back Squat", modality: "barbell")
    @bench = Exercise.create!(name: "Bench Press", modality: "barbell")
  end

  test "creates a scheduled ordered workout" do
    assert_difference "WorkoutTemplate.count", 1 do
      assert_difference "WorkoutTemplateExercise.count", 2 do
        post workout_templates_path, params: {
          workout_template: {
            name: "Upper",
            weekdays: [ "1", "4" ],
            workout_template_exercises_attributes: {
              "0" => { exercise_id: @bench.id, position: 99 },
              "1" => { exercise_id: @squat.id, position: 99 }
            }
          }
        }
      end
    end

    template = WorkoutTemplate.last
    assert_equal [ 1, 4 ], template.weekdays
    assert_equal [ @bench.id, @squat.id ], template.workout_template_exercises.pluck(:exercise_id)
    assert_redirected_to workout_templates_path
  end

  test "rejects another user's custom exercise" do
    foreign_exercise = Exercise.create!(user: users(:two), name: "Private Press", modality: "other")

    assert_no_difference [ "WorkoutTemplate.count", "WorkoutTemplateExercise.count" ] do
      post workout_templates_path, params: {
        workout_template: {
          name: "Unsafe",
          weekdays: [ "2" ],
          workout_template_exercises_attributes: {
            "0" => { exercise_id: foreign_exercise.id, position: 1 }
          }
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "reorders existing exercises without rewriting the workout" do
    template = @user.workout_templates.create!(
      name: "Strength",
      workout_template_exercises_attributes: {
        "0" => { exercise: @squat, position: 1 },
        "1" => { exercise: @bench, position: 2 }
      }
    )
    squat_item, bench_item = template.workout_template_exercises.to_a

    assert_no_difference [ "WorkoutTemplate.count", "WorkoutTemplateExercise.count" ] do
      patch workout_template_path(template), params: {
        workout_template: {
          name: "Strength",
          weekdays: [ "3" ],
          workout_template_exercises_attributes: {
            "0" => { id: bench_item.id, exercise_id: @bench.id, position: 1 },
            "1" => { id: squat_item.id, exercise_id: @squat.id, position: 2 }
          }
        }
      }
    end

    assert_redirected_to workout_templates_path
    assert_equal [ @bench.id, @squat.id ], template.reload.workout_template_exercises.pluck(:exercise_id)
  end

  test "does not expose another user's workout template" do
    foreign_template = users(:two).workout_templates.create!(
      name: "Private Day",
      workout_template_exercises_attributes: {
        "0" => { exercise: @squat, position: 1 }
      }
    )

    get edit_workout_template_path(foreign_template)

    assert_response :not_found
  end
  test "saves a logged session as a workout and opens it for scheduling" do
    squat = Exercise.create!(name: "Zzz Ctl Squat", modality: "barbell", is_compound: true)
    bench = Exercise.create!(name: "Zzz Ctl Bench", modality: "barbell", is_compound: true)
    session = @user.workout_sessions.create!(performed_at: 1.hour.ago)
    session.set_entries.create!(exercise: squat, set_index: 1, weight_kg: 100, reps: 5, rir: 2)
    session.set_entries.create!(exercise: bench, set_index: 2, weight_kg: 60, reps: 8, rir: 2)

    assert_difference "@user.workout_templates.count", 1 do
      post save_workout_session_as_workout_path(session), params: { name: "Zzz Ctl Saved" }
    end

    template = @user.workout_templates.find_by(name: "Zzz Ctl Saved")
    assert_equal [ squat.id, bench.id ], template.workout_template_exercises.order(:position).pluck(:exercise_id)
    # Straight into the editor, because scheduling it to a day is the next thing
    # anybody wants and it is the one part a session cannot supply.
    assert_redirected_to edit_workout_template_path(template)
  end

  test "a name already taken says so and creates nothing" do
    squat = Exercise.create!(name: "Zzz Ctl Dup", modality: "barbell", is_compound: true)
    @user.workout_templates.create!(name: "Zzz Ctl Clash", weekdays: [],
      workout_template_exercises_attributes: [ { exercise_id: squat.id, position: 1 } ])
    session = @user.workout_sessions.create!(performed_at: 1.hour.ago)
    session.set_entries.create!(exercise: squat, set_index: 1, weight_kg: 100, reps: 5, rir: 2)

    assert_no_difference "@user.workout_templates.count" do
      post save_workout_session_as_workout_path(session), params: { name: "Zzz Ctl Clash" }
    end

    assert_redirected_to workout_session_path(session)
    assert_match(/name/i, flash[:alert])
  end

  # Scoped to the signed-in user, so somebody else's session cannot be copied
  # into your own workouts.
  test "another account's session cannot be saved as your workout" do
    theirs = users(:two).workout_sessions.create!(performed_at: 1.hour.ago)

    assert_no_difference "WorkoutTemplate.count" do
      post save_workout_session_as_workout_path(theirs), params: { name: "Zzz Ctl Theirs" }
    end

    assert_response :not_found
  end
  # A lift with no training target logs fine and never progresses: the evaluator
  # skips it and the logger repeats last time's heaviest set. The split is where
  # you would notice, so that is where it is said.
  test "the split marks the lifts that have no training target" do
    curl = Exercise.find_or_create_by!(name: "Zzz Gap Curl") { |e| e.modality = "dumbbell" }
    template = template_for([ @squat, curl ], "Zzz Gap Lower")
    prescribe(@squat)

    get workout_templates_path

    assert_response :success
    assert_select ".template-exercises__gap", 1
    assert_select ".template-card__gap", /1 lift here has no training target/
    assert_not_nil template
  end

  test "a workout whose lifts all have targets says nothing" do
    template_for([ @squat ], "Zzz Covered Day")
    prescribe(@squat)

    get workout_templates_path

    assert_response :success
    assert_select ".template-card__gap", 0
  end

  private

  def template_for(exercises, name)
    template = @user.workout_templates.new(name: name, weekdays: [ 1 ])
    exercises.each_with_index { |exercise, index| template.workout_template_exercises.build(exercise:, position: index + 1) }
    template.save!
    template
  end

  def prescribe(exercise)
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current - 7
    )
  end
end
