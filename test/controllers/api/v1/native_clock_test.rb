require "test_helper"

# The phone and the browser keep the same clock.
#
# Every day boundary here is the user's own, and most of the rules that decide
# one read `Time.current` — which is only the user's clock because the request
# is wrapped in `Time.use_zone`. `ApplicationController` wrapped and
# `Api::V1::BaseController` did not, so the same rule meant two different things
# depending on which one answered.
class Api::V1::NativeClockTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @oats = @user.foods.create!(
      name: "Zzz Clock Oats", serving_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7
    )
    @token = sign_in_natively
  end

  # 01:30 UTC on the 11th is 19:30 on the 10th in Denver: the evening of the
  # day before, which is dinner.
  EVENING_IN_DENVER = Time.utc(2026, 6, 11, 1, 30)

  test "an evening log is filed under the same meal from the phone as from the browser" do
    travel_to EVENING_IN_DENVER do
      post api_v1_food_log_entries_path, headers: auth, as: :json,
        params: { food_log_entry: { food_id: @oats.id, quantity_grams: 50 } }
      assert_response :created

      sign_in_as(@user)
      post food_log_entries_path, params: { food_log_entry: {
        food_id: @oats.id, quantity_grams: 50, logged_at: Time.current.iso8601
      } }
    end

    phone, browser = @user.food_log_entries.order(:id).last(2)
    assert_equal "dinner", phone.meal_type
    assert_equal browser.meal_type, phone.meal_type
  end

  # One tap logs every food in the meal, filed under the meal happening now.
  test "a one-tap meal is filed under the meal happening where the user is" do
    meal = @user.meals.new(name: "Zzz Clock Meal")
    meal.meal_items.build(food: @oats, quantity_grams: 80, position: 1)
    meal.save!

    travel_to EVENING_IN_DENVER do
      post log_api_v1_meal_path(meal), headers: auth, as: :json
    end

    assert_response :created
    assert_equal "dinner", @user.food_log_entries.order(:id).last.meal_type
  end

  # The API used to answer both of these in one round trip and contradict
  # itself: the day endpoint asked the user's clock directly, the write did not.
  test "the meal the day reports is the meal a log is filed under" do
    travel_to EVENING_IN_DENVER do
      get api_v1_nutrition_path, headers: auth, as: :json
      reported = response.parsed_body.dig("data", "current_meal_type")

      post api_v1_food_log_entries_path, headers: auth, as: :json,
        params: { food_log_entry: { food_id: @oats.id, quantity_grams: 50 } }

      assert_equal reported, response.parsed_body.dig("data", "meal_type")
      assert_equal "dinner", reported
    end
  end

  test "the day a log lands on is the user's day, not the server's" do
    travel_to EVENING_IN_DENVER do
      post api_v1_food_log_entries_path, headers: auth, as: :json,
        params: { food_log_entry: { food_id: @oats.id, quantity_grams: 50 } }

      get api_v1_nutrition_path, headers: auth, as: :json
      # Still the 10th where the user is, though it is the 11th in UTC.
      assert_equal "2026-06-10", response.parsed_body.dig("data", "date")
      assert_equal 1, response.parsed_body.dig("data", "entries").length
    end
  end

  test "signing in needs no user to have a clock" do
    post api_v1_session_path, params: { email_address: @user.email_address, password: "password" }, as: :json

    assert_response :created
  end

  private

  def sign_in_natively
    post api_v1_session_path, params: { email_address: @user.email_address, password: "password" }, as: :json
    response.parsed_body.fetch("token")
  end

  def auth = { "Authorization" => "Bearer #{@token}" }
end
