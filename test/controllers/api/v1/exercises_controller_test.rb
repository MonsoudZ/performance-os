require "test_helper"

class Api::V1::ExercisesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    ExerciseCatalogImporter.new.call
  end

  teardown do
    Rack::Attack.reset!
  end

  test "returns the canonical exercise catalog" do
    get api_v1_exercises_path, as: :json

    assert_response :success
    assert_equal(
      { "returned" => 32, "total" => 32, "limit" => 50 },
      response.parsed_body.fetch("meta")
    )
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
    assert_equal(
      { "returned" => 3, "total" => 3, "limit" => 50 },
      response.parsed_body.fetch("meta")
    )
  end

  test "caps the requested limit" do
    get api_v1_exercises_path, params: { limit: 999_999 }, as: :json

    assert_response :success
    assert_equal 100, response.parsed_body.dig("meta", "limit")
    assert_equal 32, response.parsed_body.dig("meta", "returned")
    assert_equal 32, response.parsed_body.dig("meta", "total")
  end

  test "distinguishes returned records from the filtered total" do
    get api_v1_exercises_path, params: { query: "press", limit: 2 }, as: :json

    assert_response :success
    assert_equal 2, response.parsed_body.dig("meta", "returned")
    assert_equal 8, response.parsed_body.dig("meta", "total")
    assert_equal 2, response.parsed_body.dig("meta", "limit")
  end

  test "does not expose user-owned exercises" do
    Exercise.create!(user: users(:one), name: "Secret Garage Lift", modality: "other")

    get api_v1_exercises_path, params: { query: "Secret" }, as: :json

    assert_response :success
    assert_empty response.parsed_body.fetch("data")
  end

  test "rate limits the public catalog by IP" do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    Rack::Attack::EXERCISE_CATALOG_LIMIT.times do
      get api_v1_exercises_path(format: :json), headers: { "REMOTE_ADDR" => "203.0.113.10" }
      assert_response :success
    end

    get api_v1_exercises_path(format: :json), headers: { "REMOTE_ADDR" => "203.0.113.10" }

    assert_response :too_many_requests
    assert_equal "Rate limit exceeded", response.parsed_body.fetch("error")
    assert response.headers["Retry-After"].present?
  ensure
    Rack::Attack.cache.store = Rails.cache
  end
end
