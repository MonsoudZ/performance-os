require "test_helper"

class Api::V1::ExercisesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ExerciseCatalogImporter.new.call
  end

  test "returns the canonical exercise catalog" do
    get api_v1_exercises_path, as: :json

    assert_response :success
    assert_equal 32, response.parsed_body.dig("meta", "count")
    bench = response.parsed_body.fetch("data").find { |exercise| exercise.fetch("name") == "Barbell Bench Press" }
    assert_equal "barbell", bench.fetch("modality")
    assert_equal "chest", bench.fetch("muscles").first.fetch("name")
  end

  test "filters by modality and query" do
    get api_v1_exercises_path, params: { modality: "dumbbell", query: "press" }, as: :json

    assert_response :success
    assert_equal(
      [ "Dumbbell Bench Press", "Dumbbell Shoulder Press", "Incline Dumbbell Bench Press" ],
      response.parsed_body.fetch("data").pluck("name")
    )
  end

  test "does not expose user-owned exercises" do
    Exercise.create!(user: users(:one), name: "Secret Garage Lift", modality: "other")

    get api_v1_exercises_path, params: { query: "Secret" }, as: :json

    assert_response :success
    assert_empty response.parsed_body.fetch("data")
  end
end
