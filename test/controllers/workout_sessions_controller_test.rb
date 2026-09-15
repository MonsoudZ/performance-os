require "test_helper"

class WorkoutSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @exercise = Exercise.create!(name: "Back Squat", modality: "barbell")
    ExercisePrescription.create!(
      user: @user,
      exercise: @exercise,
      rep_min: 6,
      rep_max: 8,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 3,
      started_on: Date.current
    )
  end

  test "logs working sets and creates a progression decision" do
    assert_difference "WorkoutSession.count", 1 do
      assert_difference "SetEntry.count", 3 do
        assert_difference "CoachingDecision.count", 1 do
          # Session + sets persist synchronously; the progression decision is
          # produced by WorkoutProgressionRecomputeJob.
          perform_enqueued_jobs do
            post workout_sessions_path, params: {
              workout_session: {
                performed_at: Time.current,
                set_entries_attributes: {
                  "0" => set_params(1),
                  "1" => set_params(2),
                  "2" => set_params(3)
                }
              }
            }
          end
        end
      end
    end

    assert_redirected_to workout_session_path(WorkoutSession.last)
    assert_equal "increase", CoachingDecision.last.output["status"]
  end

  test "new workout renders prescribed set count instead of fixed blank rows" do
    get new_workout_session_path

    assert_response :success
    assert_select "[data-workout-log-target='rows'] > [data-workout-log-target='row']", count: 3
    assert_select "input[value='8']", minimum: 3
    assert_select "[data-workout-log-target='volume']", text: "0 kg"
  end

  test "scheduled template prefills exercises in template order and snapshots the plan" do
    bench = Exercise.create!(name: "Bench Press", modality: "barbell")
    ExercisePrescription.create!(
      user: @user,
      exercise: bench,
      rep_min: 8,
      rep_max: 10,
      target_rir_min: 1,
      target_rir_max: 2,
      increment_kg: 2.5,
      working_sets: 2,
      started_on: Date.current
    )
    template = @user.workout_templates.create!(
      name: "Upper",
      weekdays: [ Date.current.wday ],
      workout_template_exercises_attributes: {
        "0" => { exercise: bench, position: 1 },
        "1" => { exercise: @exercise, position: 2 }
      }
    )

    get new_workout_session_path(workout_template_id: template.id)

    assert_response :success
    assert_select "[data-workout-log-target='rows'] > [data-workout-log-target='row']", count: 5
    exercise_names = css_select("[data-workout-log-target='rows'] .set-exercise strong").map(&:text)
    assert_equal [ "Bench Press", "Bench Press", "Back Squat", "Back Squat", "Back Squat" ], exercise_names

    assert_difference "WorkoutSession.count", 1 do
      post workout_sessions_path, params: {
        workout_session: {
          workout_template_id: template.id,
          performed_at: Time.current,
          set_entries_attributes: {
            "0" => set_params(1)
          }
        }
      }
    end

    workout = WorkoutSession.last
    assert_equal template, workout.workout_template
    assert_equal "Upper", workout.template_name
    assert_equal 5, workout.planned_working_sets
  end

  test "does not expose another user's workout" do
    other_workout = users(:two).workout_sessions.create!(performed_at: Time.current)

    get workout_session_path(other_workout)

    assert_response :not_found
  end

  test "does not attach another user's workout template" do
    foreign_template = users(:two).workout_templates.create!(
      name: "Private Day",
      workout_template_exercises_attributes: {
        "0" => { exercise: @exercise, position: 1 }
      }
    )

    post workout_sessions_path, params: {
      workout_session: {
        workout_template_id: foreign_template.id,
        performed_at: Time.current,
        set_entries_attributes: {
          "0" => set_params(1)
        }
      }
    }

    assert_nil WorkoutSession.last.workout_template
    assert_empty WorkoutSession.last.template_snapshot
  end

  test "rejects another user's custom exercise in nested sets" do
    foreign_exercise = Exercise.create!(user: users(:two), name: "Private Lift", modality: "other")

    assert_no_difference [ "WorkoutSession.count", "SetEntry.count" ] do
      post workout_sessions_path, params: {
        workout_session: {
          performed_at: Time.current,
          set_entries_attributes: {
            "0" => set_params(1).merge(exercise_id: foreign_exercise.id)
          }
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "edits a logged set and re-evaluates progression" do
    workout = create_logged_workout
    decision = DoubleProgressionEvaluator.new(workout).call.first

    assert_enqueued_with(job: WorkoutProgressionRecomputeJob) do
      patch workout_session_path(workout), params: {
        workout_session: {
          performed_at: workout.performed_at,
          set_entries_attributes: existing_set_params(workout, 1 => { reps: 6 })
        }
      }
    end

    assert_equal 6, workout.set_entries.order(:set_index).first.reload.reps
    assert decision.reload.retracted_at
    assert_equal "workout_session_corrected", decision.retraction_reason
    assert_redirected_to workout_session_path(workout)
  end

  test "removes a set on edit" do
    workout = create_logged_workout

    assert_difference "SetEntry.count", -1 do
      patch workout_session_path(workout), params: {
        workout_session: {
          performed_at: workout.performed_at,
          set_entries_attributes: existing_set_params(workout, 3 => { _destroy: "1" })
        }
      }
    end
  end

  test "deletes a workout and recomputes the plan" do
    workout = create_logged_workout
    decision = DoubleProgressionEvaluator.new(workout).call.first
    parent = @user.coaching_decisions.create!(
      decision_type: "daily_training",
      rule_key: "daily_training_orchestrator.v1",
      rule_version: "1.0.0",
      inputs: { "plan_date" => Date.current.iso8601 },
      output: {},
      confidence: "high"
    )
    parent.child_links.create!(child_decision: decision, role: "progression")

    assert_enqueued_with(job: TrainingPlanRecomputeJob) do
      assert_difference "WorkoutSession.count", -1 do
        delete workout_session_path(workout)
      end
    end

    assert_equal 0, SetEntry.where(workout_session_id: workout.id).count
    assert decision.reload.retracted_at
    assert_equal "workout_session_deleted", decision.retraction_reason
    assert parent.reload.retracted_at
    assert_equal "workout_session_deleted", parent.retraction_reason
    assert_redirected_to root_path
  end

  test "cannot edit another user's workout" do
    other = users(:two).workout_sessions.create!(performed_at: Time.current)

    get edit_workout_session_path(other)

    assert_response :not_found
  end

  test "cannot delete another user's workout" do
    other = users(:two).workout_sessions.create!(performed_at: Time.current)

    delete workout_session_path(other)

    assert_response :not_found
    assert WorkoutSession.exists?(other.id)
  end

  test "lists logged workouts newest first" do
    exercise = Exercise.create!(name: "Zzz Index Squat", modality: "barbell")
    older = @user.workout_sessions.create!(performed_at: 3.days.ago)
    older.set_entries.create!(exercise:, set_index: 1, weight_kg: 100, reps: 5, rir: 1)
    newer = @user.workout_sessions.create!(performed_at: 1.day.ago)
    newer.set_entries.create!(exercise:, set_index: 1, weight_kg: 105, reps: 5, rir: 1)

    get workout_sessions_path

    assert_response :success
    assert_select "h1", "Logged workouts."
    assert_select ".appearance", 2
    listed = css_select(".appearance .date").map(&:text)
    assert_equal listed.sort.reverse, listed, "newest session first"
  end

  test "the workout list shows an empty state before anything is logged" do
    get workout_sessions_path

    assert_response :success
    assert_select ".empty-state", 1
    assert_select ".appearance", 0
  end

  test "the workout list does not show another user's sessions" do
    users(:two).workout_sessions.create!(performed_at: 1.day.ago)

    get workout_sessions_path

    assert_select ".appearance", 0
  end

  test "the session shows what it no longer recommends after a correction" do
    exercise = Exercise.create!(name: "Zzz Withdrawn Squat", modality: "barbell")
    session = @user.workout_sessions.create!(performed_at: 1.day.ago)
    session.set_entries.create!(exercise:, set_index: 1, weight_kg: 100, reps: 8, rir: 1)
    withdrawn = progression_decision(session, exercise, headline: "Add 2.5 kg next time")
    withdrawn.retract!(reason: "workout_session_corrected")
    progression_decision(session, exercise, headline: "Keep the load", status: "hold")

    get workout_session_path(session)

    assert_response :success
    assert_select ".decision-trail__item.is-retracted", 1
    assert_select ".decision-trail__retracted", text: /Withdrawn .* because the workout behind it was corrected/
    assert_select ".decision-trail__exercise", { text: "Zzz Withdrawn Squat" },
      "a session covers several lifts, so a withdrawn recommendation has to name its own"
  end

  test "a session with nothing withdrawn does not show the section" do
    exercise = Exercise.create!(name: "Zzz Clean Squat", modality: "barbell")
    session = @user.workout_sessions.create!(performed_at: 1.day.ago)
    session.set_entries.create!(exercise:, set_index: 1, weight_kg: 100, reps: 8, rir: 1)
    progression_decision(session, exercise)

    get workout_session_path(session)

    assert_response :success
    assert_select ".decision-trail__item", 0
  end

  test "correcting a workout withdraws what it recommended and says so on the page" do
    exercise = Exercise.create!(name: "Zzz Corrected Squat", modality: "barbell")
    prescribe(exercise)
    session = @user.workout_sessions.create!(performed_at: Time.current)
    entry = session.set_entries.create!(exercise:, set_index: 1, weight_kg: 100, reps: 8, rir: 1)
    progression_decision(session, exercise)

    patch workout_session_path(session), params: {
      workout_session: {
        performed_at: session.performed_at,
        set_entries_attributes: { "0" => { id: entry.id, weight_kg: 90, reps: 5, rir: 3 } }
      }
    }

    follow_redirect!

    assert_response :success
    assert_select ".decision-trail__item.is-retracted", minimum: 1
    assert_equal 1, @user.coaching_decisions.withdrawn.count
  end

  def progression_decision(session, exercise, headline: "Add 2.5 kg next time", status: "increase")
    CoachingDecision.create!(
      user: @user,
      decision_type: "double_progression",
      rule_key: DoubleProgressionEvaluator::RULE_KEY,
      rule_version: DoubleProgressionEvaluator::RULE_VERSION,
      inputs: {
        "workout_session_id" => session.id,
        "exercise_id" => exercise.id,
        "exercise_name" => exercise.name
      },
      output: {
        "status" => status,
        "headline" => headline,
        "guidance" => "Guidance text.",
        "current_weight_kg" => 100.0,
        "next_weight_kg" => status == "increase" ? 102.5 : 100.0
      },
      citations: [],
      confidence: "high"
    )
  end

  def prescribe(exercise)
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 6, rep_max: 8,
      target_rir_min: 1, target_rir_max: 2, increment_kg: 2.5,
      working_sets: 3, started_on: Date.current
    )
  end

  private

  def set_params(index)
    {
      exercise_id: @exercise.id,
      set_index: index,
      weight_kg: 100,
      reps: 8,
      rir: 1
    }
  end

  def create_logged_workout
    workout = @user.workout_sessions.create!(performed_at: Time.current)
    3.times do |i|
      workout.set_entries.create!(exercise: @exercise, set_index: i + 1, weight_kg: 100, reps: 8, rir: 1)
    end
    workout
  end

  def existing_set_params(workout, changes = {})
    workout.set_entries.order(:set_index).each_with_index.to_h do |set, i|
      attributes = {
        id: set.id,
        exercise_id: set.exercise_id,
        set_index: set.set_index,
        weight_kg: set.weight_kg,
        reps: set.reps,
        rir: set.rir,
        is_warmup: set.is_warmup
      }.merge(changes[set.set_index] || {})
      [ i.to_s, attributes ]
    end
  end

  test "the delete button on a session looks like the destructive action it is" do
    workout = @user.workout_sessions.create!(performed_at: Time.current)

    get workout_session_path(workout)

    assert_response :success
    # It carried a topbar class that renders muted text with no background — a
    # destructive action that looked like a caption. The class itself is gone
    # now, so asserting its absence would assert nothing; what still has to hold
    # is that the control is styled as the destructive action it is.
    assert_select "form[action=?] button.text-button--danger", workout_session_path(workout)
  end
end
