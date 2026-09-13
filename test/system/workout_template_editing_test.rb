require "application_system_test_case"

# The template editor builds the exercise order client-side: rows are appended
# from a <template>, reordered by swapping DOM nodes, and removed either by
# deletion or by flipping a _destroy flag. The position field every row carries
# is rewritten on each change, and that field is what the server persists — so a
# reordering bug here is silently saved as the user's real workout order.
class WorkoutTemplateEditingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @squat = Exercise.create!(name: "Zzz Tpl Squat", modality: "barbell")
    @bench = Exercise.create!(name: "Zzz Tpl Bench", modality: "barbell")
    @row = Exercise.create!(name: "Zzz Tpl Row", modality: "barbell")
  end

  test "builds a template with several exercises in the chosen order" do
    sign_in @user
    visit new_workout_template_path

    fill_in "Workout name", with: "Zzz Upper A"
    check "Mon"

    select "Zzz Tpl Squat", from: exercise_select_name(0)
    click_on "Add exercise"
    select "Zzz Tpl Bench", from: exercise_select_name(1)
    click_on "Add exercise"
    select "Zzz Tpl Row", from: exercise_select_name(2)

    assert_selector ".template-editor__row", count: 3

    click_on "Save workout"
    assert_current_path workout_templates_path, wait: 10

    template = @user.workout_templates.find_by!(name: "Zzz Upper A")
    ordered = template.workout_template_exercises.order(:position).map { |item| item.exercise.name }

    assert_equal [ "Zzz Tpl Squat", "Zzz Tpl Bench", "Zzz Tpl Row" ], ordered
    assert_equal [ 1, 2, 3 ], template.workout_template_exercises.order(:position).map(&:position)
  end

  test "moving a row up rewrites the positions that get saved" do
    template = create_template("Zzz Reorder", [ @squat, @bench, @row ])
    sign_in @user
    visit edit_workout_template_path(template)

    assert_equal %w[1 2 3], position_values

    # Move the third row above the second.
    all(".template-editor__row")[2].find("button[aria-label='Move exercise up']").click

    assert_equal %w[1 2 3], position_values, "positions stay contiguous"
    assert_equal [ "Zzz Tpl Squat", "Zzz Tpl Row", "Zzz Tpl Bench" ], selected_exercise_names,
      "the row moved in the DOM"

    click_on "Update workout"
    assert_current_path workout_templates_path, wait: 10

    ordered = template.reload.workout_template_exercises.order(:position).map { |item| item.exercise.name }

    assert_equal [ "Zzz Tpl Squat", "Zzz Tpl Row", "Zzz Tpl Bench" ], ordered,
      "the reordering the user saw is the order that persisted"
  end

  test "moving the first row up and the last row down does nothing" do
    template = create_template("Zzz Edges", [ @squat, @bench ])
    sign_in @user
    visit edit_workout_template_path(template)

    all(".template-editor__row").first.find("button[aria-label='Move exercise up']").click
    all(".template-editor__row").last.find("button[aria-label='Move exercise down']").click

    assert_equal [ "Zzz Tpl Squat", "Zzz Tpl Bench" ], selected_exercise_names
    assert_equal %w[1 2], position_values
  end

  test "removing a persisted row marks it for destruction and renumbers the rest" do
    template = create_template("Zzz Removal", [ @squat, @bench, @row ])
    sign_in @user
    visit edit_workout_template_path(template)

    all(".template-editor__row")[0].find("button[aria-label='Remove exercise']").click

    # A persisted row is hidden and flagged rather than dropped, so Rails can
    # destroy the record through nested attributes.
    assert_selector ".template-editor__row", count: 2, visible: true
    assert_equal %w[1 2], position_values
    assert_equal [ "Zzz Tpl Bench", "Zzz Tpl Row" ], selected_exercise_names

    click_on "Update workout"
    assert_current_path workout_templates_path, wait: 10

    ordered = template.reload.workout_template_exercises.order(:position).map { |item| item.exercise.name }

    assert_equal [ "Zzz Tpl Bench", "Zzz Tpl Row" ], ordered
  end

  test "removing an unsaved row drops it outright" do
    sign_in @user
    visit new_workout_template_path

    click_on "Add exercise"

    assert_selector ".template-editor__row", count: 2

    all(".template-editor__row").last.find("button[aria-label='Remove exercise']").click

    assert_selector ".template-editor__row", count: 1
    assert_equal %w[1], position_values
  end

  private

  # Capybara's `all` skips hidden rows, so this reads the position of exactly the
  # rows a user can see. The field itself is type=hidden, hence visible: :all.
  def position_values
    all(".template-editor__row").map do |row|
      row.find("[data-template-editor-target='position']", visible: :all).value
    end
  end

  def selected_exercise_names
    all(".template-editor__row select").map { |select| select.value.presence }
      .compact
      .map { |id| Exercise.find(id).name }
  end

  def exercise_select_name(index)
    all(".template-editor__row select")[index][:name]
  end

  # A template validates that it has at least one exercise, so the rows have to
  # go in with it rather than after it.
  def create_template(name, exercises)
    @user.workout_templates.create!(
      name: name,
      weekdays: [ 1 ],
      workout_template_exercises_attributes: exercises.each_with_index.map do |exercise, index|
        { exercise_id: exercise.id, position: index + 1 }
      end
    )
  end
end
