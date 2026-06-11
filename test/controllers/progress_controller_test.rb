require "test_helper"

class ProgressControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "renders the progress page with volume and strength sections" do
    bench = Exercise.create!(name: "Bench", modality: "barbell")
    chest = MuscleGroup.create!(name: "chest")
    bench.exercise_muscle_contributions.create!(muscle_group: chest, role: "primary", fraction: 1.0)
    workout = @user.workout_sessions.create!(performed_at: Time.current)
    3.times { |i| workout.set_entries.create!(exercise: bench, set_index: i + 1, weight_kg: 100, reps: 8, rir: 1) }

    get progress_path

    assert_response :success
    assert_select "h1", "What the work is building."
    assert_select ".volume-row", minimum: 1
    assert_select ".progress-card strong", text: "Bench"
  end

  test "renders empty states with no logged work" do
    get progress_path

    assert_response :success
    assert_select ".empty-state", minimum: 1
  end
end
