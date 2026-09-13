require "test_helper"

# The database stores kilograms and centimetres no matter who is looking. These
# assert the two boundaries where that can go wrong: what an imperial user reads,
# and what lands in the column when they type pounds into a form.
class ImperialUnitsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:two)
    assert_predicate @user, :imperial?, "fixture :two is the imperial user"
    sign_in_as(@user)
    @exercise = Exercise.create!(name: "Zzz Imperial Squat", modality: "barbell")
  end

  test "a body weight typed in pounds is stored in kilograms" do
    post body_metrics_path, params: { body_metric: { measured_on: Date.current, weight_kg: 200 } }

    assert_in_delta 90.72, BodyMetric.order(:id).last.weight_kg.to_f, 0.01
  end

  test "a metric user's body weight is stored unchanged" do
    sign_in_as(users(:one))

    post body_metrics_path, params: { body_metric: { measured_on: Date.current, weight_kg: 90 } }

    assert_in_delta 90.0, BodyMetric.order(:id).last.weight_kg.to_f, 0.01
  end

  test "set weights typed in pounds are stored in kilograms" do
    post workout_sessions_path, params: {
      workout_session: {
        performed_at: Time.current,
        set_entries_attributes: {
          "0" => { exercise_id: @exercise.id, set_index: 1, weight_kg: 225, reps: 5, rir: 2 },
          "1" => { exercise_id: @exercise.id, set_index: 2, weight_kg: 135, reps: 8, rir: 3 }
        }
      }
    }

    stored = SetEntry.where(exercise: @exercise).order(:set_index).pluck(:weight_kg).map(&:to_f)

    assert_in_delta 102.06, stored.first, 0.01
    assert_in_delta 61.23, stored.second, 0.01
  end

  test "a blank set weight stays blank rather than becoming zero" do
    post workout_sessions_path, params: {
      workout_session: {
        performed_at: Time.current,
        set_entries_attributes: {
          "0" => { exercise_id: @exercise.id, set_index: 1, weight_kg: "", reps: 12, rir: 1 }
        }
      }
    }

    assert_nil SetEntry.where(exercise: @exercise).order(:set_index).first&.weight_kg
  end

  test "a load increment typed in pounds is stored in kilograms" do
    post exercise_prescriptions_path, params: {
      exercise_prescription: {
        exercise_id: @exercise.id,
        rep_min: 6, rep_max: 8,
        target_rir_min: 1, target_rir_max: 2,
        increment_kg: 5,
        working_sets: 3,
        started_on: Date.current
      }
    }

    assert_in_delta 2.27, ExercisePrescription.order(:id).last.increment_kg.to_f, 0.01
  end

  test "a height typed in inches is stored in centimetres" do
    patch profile_path, params: { user: { height_cm: 70 } }

    assert_in_delta 177.8, @user.reload.height_cm.to_f, 0.05
  end

  test "the workout logger labels its weight column in pounds" do
    prescribe

    get new_workout_session_path

    assert_response :success
    assert_select ".set-table__header span", text: "lb"
    assert_select ".set-table__header span", text: "kg", count: 0
  end

  test "the training-target form asks for pounds and shows the stored value in pounds" do
    get edit_exercise_prescription_path(prescribe(increment_kg: 2.27))

    assert_response :success
    assert_select "label", text: /Load increment \(lb\)/
    assert_select "input[name='exercise_prescription[increment_kg]'][value='5.0']"
  end

  test "the exercise page reports history in pounds" do
    session = @user.workout_sessions.create!(performed_at: 1.day.ago)
    session.set_entries.create!(exercise: @exercise, set_index: 1, weight_kg: 102.06, reps: 5, rir: 1)

    get exercise_path(@exercise)

    assert_response :success
    assert_match(/225 lb/, css_select(".lift-stats").text, "the summary tiles read in pounds")
    assert_select ".appearance__set", text: /225 lb × 5/
  end

  test "a metric user still reads kilograms on the same pages" do
    sign_in_as(users(:one))
    session = users(:one).workout_sessions.create!(performed_at: 1.day.ago)
    session.set_entries.create!(exercise: @exercise, set_index: 1, weight_kg: 100, reps: 5, rir: 1)

    get exercise_path(@exercise)

    assert_response :success
    assert_select ".appearance__set", text: /100 kg × 5/
  end

  test "a metric user's logger still labels its column in kilograms" do
    sign_in_as(users(:one))
    users(:one).exercise_prescriptions.create!(
      exercise: @exercise, rep_min: 6, rep_max: 8,
      target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current
    )

    get new_workout_session_path

    assert_response :success
    assert_select ".set-table__header span", text: "kg"
    assert_select ".set-table__header span", text: "lb", count: 0
  end

  test "a weight survives a pounds round trip through the form" do
    post body_metrics_path, params: { body_metric: { measured_on: Date.current, weight_kg: 187.5 } }
    metric = BodyMetric.order(:id).last

    get nutrition_path

    assert_response :success
    assert_select ".compact-list__item strong", { text: /187\.5 lb/ },
      "what the user typed is what the user reads back"
    assert_in_delta 85.05, metric.weight_kg.to_f, 0.01
  end

  private

  def prescribe(increment_kg: 2.5)
    @user.exercise_prescriptions.create!(
      exercise: @exercise,
      rep_min: 6, rep_max: 8,
      target_rir_min: 1, target_rir_max: 2,
      increment_kg: increment_kg,
      working_sets: 3,
      started_on: Date.current
    )
  end
end
