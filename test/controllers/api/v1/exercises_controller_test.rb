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
    total = Exercise.where(user_id: nil).count
    meta = response.parsed_body.fetch("meta")
    # Asserted against the catalog rather than a number written here: the catalog
    # grows, and a test that pins its size fails for the wrong reason.
    assert_equal total, meta.fetch("total")
    assert_equal 50, meta.fetch("limit")
    assert_equal 0, meta.fetch("offset")
    assert_equal [ total, 50 ].min, meta.fetch("returned")
    assert_equal "60", response.headers["X-RateLimit-Limit"]
    assert_equal "59", response.headers["X-RateLimit-Remaining"]
    bench = response.parsed_body.fetch("data").find { |exercise| exercise.fetch("name") == "Barbell Bench Press" }
    assert_equal "barbell", bench.fetch("modality")
    assert_equal "chest", bench.fetch("muscles").first.fetch("name")
  end

  test "filters by modality and query" do
    get api_v1_exercises_path, params: { modality: "dumbbell", query: "press" }, as: :json

    assert_response :success
    names = response.parsed_body.fetch("data").pluck("name")
    assert_includes names, "Dumbbell Bench Press"
    assert_includes names, "Incline Dumbbell Bench Press"
    assert names.all? { |name| name.match?(/press/i) }, "every result should match the query"

    meta = response.parsed_body.fetch("meta")
    assert_equal names.size, meta.fetch("returned")
    assert_equal names.size, meta.fetch("total")
    assert_nil meta.fetch("next_offset"), "a filtered page that fits has nothing after it"
  end

  # The catalog outgrew MAX_LIMIT, so one request stopped being enough and a
  # client needs to be told where to continue from.
  test "pages through a catalog larger than one request" do
    get api_v1_exercises_path, params: { limit: 100 }, as: :json
    first = response.parsed_body
    total = Exercise.where(user_id: nil).count

    assert_equal 100, first.dig("meta", "returned")
    assert_equal 100, first.dig("meta", "next_offset")

    get api_v1_exercises_path, params: { limit: 100, offset: first.dig("meta", "next_offset") }, as: :json
    second = response.parsed_body

    assert_equal total - 100, second.dig("meta", "returned")
    assert_nil second.dig("meta", "next_offset"), "the last page says it is the last"

    names = first.fetch("data").pluck("name") + second.fetch("data").pluck("name")
    assert_equal total, names.uniq.size, "paging should cover the catalog exactly once"
  end

  test "a negative offset is treated as the beginning" do
    get api_v1_exercises_path, params: { offset: -5 }, as: :json

    assert_equal 0, response.parsed_body.dig("meta", "offset")
  end

  test "caps the requested limit" do
    get api_v1_exercises_path, params: { limit: 999_999 }, as: :json

    assert_response :success
    total = Exercise.where(user_id: nil).count
    assert_equal 100, response.parsed_body.dig("meta", "limit")
    assert_equal [ total, 100 ].min, response.parsed_body.dig("meta", "returned")
    assert_equal total, response.parsed_body.dig("meta", "total")
  end

  test "distinguishes returned records from the filtered total" do
    get api_v1_exercises_path, params: { query: "press", limit: 2 }, as: :json

    assert_response :success
    press_total = Exercise.where(user_id: nil).where("name ILIKE ?", "%press%").count
    assert_operator press_total, :>, 2, "needs more matches than the limit to exercise the cap"
    assert_equal 2, response.parsed_body.dig("meta", "returned")
    assert_equal press_total, response.parsed_body.dig("meta", "total")
    assert_equal 2, response.parsed_body.dig("meta", "limit")
  end

  test "does not expose user-owned exercises" do
    Exercise.create!(user: users(:one), name: "Secret Garage Lift", modality: "other")

    get api_v1_exercises_path, params: { query: "Secret" }, as: :json

    assert_response :success
    assert_empty response.parsed_body.fetch("data")
  end

  test "rate limits the public catalog by IP" do
    Rack::Attack::EXERCISE_CATALOG_LIMIT.times do |request_number|
      proxy_ip = "10.0.0.#{request_number % 2 + 1}"
      get api_v1_exercises_path(format: :json), headers: {
        "X-Forwarded-For" => "203.0.113.10, #{proxy_ip}",
        "REMOTE_ADDR" => proxy_ip
      }
      assert_response :success
    end

    get api_v1_exercises_path(format: :json), headers: {
      "X-Forwarded-For" => "203.0.113.10, 10.0.0.3",
      "REMOTE_ADDR" => "10.0.0.3"
    }

    assert_response :too_many_requests
    assert_equal "Rate limit exceeded", response.parsed_body.fetch("error")
    assert response.headers["Retry-After"].present?
    assert_equal "60", response.headers["X-RateLimit-Limit"]
    assert_equal "0", response.headers["X-RateLimit-Remaining"]
  end
end
