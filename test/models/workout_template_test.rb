require "test_helper"

class WorkoutTemplateTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @squat = Exercise.create!(name: "Zzz Tmpl Squat", modality: "barbell")
    @bench = Exercise.create!(name: "Zzz Tmpl Bench", modality: "barbell")
  end

  test "a template needs a name and at least one exercise" do
    assert_not @user.workout_templates.build(name: "Zzz Empty", weekdays: [ 1 ]).valid?,
      "a template with no exercises has nothing to log"
    assert build(name: "").invalid?
  end

  test "a name is unique per user but not across users" do
    create(name: "Zzz Upper")

    assert_not build(name: "Zzz Upper").valid?
    assert build(name: "Zzz Upper", user: users(:two)).valid?
  end

  test "a name is trimmed before it is stored or compared" do
    template = create(name: "  Zzz Padded  ")

    assert_equal "Zzz Padded", template.name
    assert_not build(name: "Zzz Padded ").valid?, "the trimmed name collides"
  end

  test "weekdays must be real days of the week" do
    assert build(weekdays: [ 0, 6 ]).valid?
    assert_not build(weekdays: [ 7 ]).valid?
    assert_not build(weekdays: [ -1 ]).valid?
  end

  test "an unscheduled template is allowed and says so" do
    template = create(weekdays: [])

    assert_predicate template, :valid?
    assert_equal "Unscheduled", template.schedule_label
  end

  test "schedule_label lists the days in week order" do
    template = create(weekdays: [ 5, 1, 3 ])

    assert_equal "Mon · Wed · Fri", template.schedule_label
  end

  test "scheduled_on? and the scope agree about a date" do
    monday_template = create(name: "Zzz Monday", weekdays: [ 1 ])
    monday = Date.new(2026, 3, 2) # a Monday
    tuesday = Date.new(2026, 3, 3)

    assert_predicate monday.wday, :positive?
    assert monday_template.scheduled_on?(monday)
    assert_not monday_template.scheduled_on?(tuesday)
    assert_includes @user.workout_templates.scheduled_on(monday), monday_template
    assert_not_includes @user.workout_templates.scheduled_on(tuesday), monday_template
  end

  test "exercises come back in the order they were positioned" do
    template = @user.workout_templates.create!(
      name: "Zzz Ordered",
      weekdays: [ 1 ],
      workout_template_exercises_attributes: [
        { exercise_id: @bench.id, position: 2 },
        { exercise_id: @squat.id, position: 1 }
      ]
    )

    assert_equal [ @squat, @bench ], template.reload.workout_template_exercises.map(&:exercise)
  end

  test "removing the last exercise is refused rather than leaving an empty template" do
    template = create
    item = template.workout_template_exercises.first

    template.assign_attributes(workout_template_exercises_attributes: [ { id: item.id, _destroy: "1" } ])

    assert_not template.valid?
    assert_includes template.errors.attribute_names, :workout_template_exercises
  end

  test "deleting a template takes its rows but leaves the logged sessions" do
    template = create
    session = @user.workout_sessions.create!(performed_at: 1.day.ago, workout_template: template)

    assert_difference -> { WorkoutTemplateExercise.count }, -1 do
      template.destroy
    end

    assert session.reload.persisted?, "a logged workout outlives the template it came from"
    assert_nil session.workout_template_id
  end

  private

  def build(name: "Zzz Template", weekdays: [ 1 ], user: @user, exercises: [ @squat ])
    user.workout_templates.build(
      name: name,
      weekdays: weekdays,
      workout_template_exercises_attributes: exercises.each_with_index.map do |exercise, index|
        { exercise_id: exercise.id, position: index + 1 }
      end
    )
  end

  def create(**attributes)
    build(**attributes).tap(&:save!)
  end
end
