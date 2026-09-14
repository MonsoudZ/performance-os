require "test_helper"

class WorkoutTemplateFromSessionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @squat = catalog("Zzz Saved Squat")
    @bench = catalog("Zzz Saved Bench")
    @curl = catalog("Zzz Saved Curl")
  end

  test "keeps the exercises in the order they were performed, each once" do
    session = log(
      [ @squat, 1 ], [ @squat, 2 ], [ @bench, 3 ], [ @bench, 4 ], [ @curl, 5 ], [ @squat, 6 ]
    )

    template = WorkoutTemplateFromSession.new(session, name: "Zzz Saved Day").call

    assert template.persisted?
    assert_equal [ @squat.id, @bench.id, @curl.id ],
      template.workout_template_exercises.order(:position).pluck(:exercise_id)
    assert_equal [ 1, 2, 3 ], template.workout_template_exercises.order(:position).pluck(:position)
  end

  # Warming up on something is not training it, so it does not become part of
  # the workout you saved.
  test "an exercise that was only warmed up is left out" do
    session = log([ @squat, 1 ], [ @bench, 2, warmup: true ])

    template = WorkoutTemplateFromSession.new(session, name: "Zzz Saved Warmups").call

    assert_equal [ @squat.id ], template.workout_template_exercises.pluck(:exercise_id)
  end

  # But a session that was nothing but warm-ups is still worth saving as what it
  # was, rather than failing as an empty workout.
  test "a session of only warm-ups keeps its exercises" do
    session = log([ @squat, 1, warmup: true ], [ @bench, 2, warmup: true ])

    template = WorkoutTemplateFromSession.new(session, name: "Zzz Saved All Warmups").call

    assert template.persisted?
    assert_equal [ @squat.id, @bench.id ], template.workout_template_exercises.order(:position).pluck(:exercise_id)
  end

  test "it is saved to the user who logged the session" do
    template = WorkoutTemplateFromSession.new(log([ @squat, 1 ]), name: "Zzz Saved Owner").call

    assert_equal @user, template.user
    assert_empty users(:two).workout_templates.where(name: "Zzz Saved Owner")
  end

  test "a name already in use is rejected rather than silently renamed" do
    @user.workout_templates.create!(name: "Zzz Saved Taken", weekdays: [],
      workout_template_exercises_attributes: [ { exercise_id: @squat.id, position: 1 } ])

    template = WorkoutTemplateFromSession.new(log([ @bench, 1 ]), name: "Zzz Saved Taken").call

    assert_not template.persisted?
    assert_match(/name/i, template.errors.full_messages.to_sentence)
  end

  # The prefilled name has to work without being edited, and running the same
  # template twice then saving both is the ordinary case.
  test "the suggested name steps around one already taken" do
    session = log([ @squat, 1 ])
    session.update!(template_snapshot: { "name" => "Zzz Saved Push" })

    assert_equal "Zzz Saved Push", WorkoutTemplateFromSession.suggested_name(session)

    WorkoutTemplateFromSession.new(session).call
    assert_equal "Zzz Saved Push 2", WorkoutTemplateFromSession.suggested_name(session.reload)

    WorkoutTemplateFromSession.new(session).call
    assert_equal "Zzz Saved Push 3", WorkoutTemplateFromSession.suggested_name(session.reload)
  end

  test "a session with no template of its own is named after the day it happened" do
    session = log([ @squat, 1 ])
    session.update!(performed_at: Time.zone.parse("2026-03-02 18:00"), template_snapshot: {})

    assert_equal "Monday workout", WorkoutTemplateFromSession.suggested_name(session)
  end

  test "the suggested name is what gets used when none is given" do
    session = log([ @squat, 1 ])
    session.update!(template_snapshot: { "name" => "Zzz Saved Default" })

    assert_equal "Zzz Saved Default", WorkoutTemplateFromSession.new(session).call.name
  end

  test "a blank name falls back to the suggestion rather than failing" do
    session = log([ @squat, 1 ])
    session.update!(template_snapshot: { "name" => "Zzz Saved Blank" })

    assert_equal "Zzz Saved Blank", WorkoutTemplateFromSession.new(session, name: "   ").call.name
  end

  private

  def catalog(name)
    Exercise.create!(name: name, modality: "barbell", is_compound: true)
  end

  def log(*sets)
    session = @user.workout_sessions.create!(performed_at: 1.hour.ago)
    sets.each do |exercise, index, options|
      session.set_entries.create!(
        exercise: exercise, set_index: index, weight_kg: 100, reps: 5, rir: 2,
        is_warmup: options.is_a?(Hash) ? options.fetch(:warmup, false) : false
      )
    end
    session
  end
end
