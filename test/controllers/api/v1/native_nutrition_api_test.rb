require "test_helper"

# Nutrition and the daily check-in, driven the way the phone drives them.
#
# Two rules are worth more than the rest of this file put together, and both are
# the kind that fail silently:
#
#   - the four readiness ratings are never filled in for the user, because a
#     score built from nothing is worse than no score;
#   - a logged entry's macros are computed from the food and the portion, not
#     taken from whoever is asking.
class Api::V1::NativeNutritionApiTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    @user = users(:one)
    @token = sign_in_natively
    @oats = food("Zzz Api Oats", kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7)
    @whey = food("Zzz Api Whey", kcal: 400, protein_g: 80, carb_g: 8, fat_g: 6)
  end

  teardown { Rack::Attack.reset! }

  # ---- the day ----------------------------------------------------------

  test "the day carries what was logged and the verdict the engine wrote" do
    log(@oats, grams: 80)
    perform_enqueued_jobs { post_entry(@whey, grams: 30) }

    get api_v1_nutrition_path, headers: auth, as: :json

    assert_response :success
    day = response.parsed_body.fetch("data")
    assert_equal @user.local_date.iso8601, day.fetch("date")
    assert_equal [ "Zzz Api Whey", "Zzz Api Oats" ], day.fetch("entries").map { |e| e.dig("food", "name") }

    # The numbers come off the decision rather than being summed again here, so
    # what the client shows is the same figure the audit page shows.
    decision = day.fetch("decision")
    assert_equal "daily_nutrition", decision.fetch("decision_type")
    assert_in_delta 424.0, decision.dig("output", "totals", "kcal"), 0.5
    assert decision.fetch("id").present?, "the decision id is the way into its audit trail"
  end

  test "a day nothing has recomputed yet has entries but no verdict" do
    log(@oats, grams: 80)

    get api_v1_nutrition_path, headers: auth, as: :json

    assert_response :success
    assert_equal 1, response.parsed_body.dig("data", "entries").length
    assert_nil response.parsed_body.dig("data", "decision")
  end

  test "a withdrawn verdict is not the answer to what the engine says today" do
    perform_enqueued_jobs { post_entry(@oats, grams: 80) }
    @user.coaching_decisions.of_type("daily_nutrition").last.retract!(reason: "test")

    get api_v1_nutrition_path, headers: auth, as: :json

    assert_nil response.parsed_body.dig("data", "decision")
  end

  test "asking for another day reads that day rather than today" do
    log(@oats, grams: 80, at: 2.days.ago)

    get api_v1_nutrition_path, params: { date: 2.days.ago.to_date.iso8601 }, headers: auth, as: :json

    assert_response :success
    assert_equal 1, response.parsed_body.dig("data", "entries").length

    get api_v1_nutrition_path, headers: auth, as: :json
    assert_equal 0, response.parsed_body.dig("data", "entries").length
  end

  # Silently reading a broken date as today would have a client go on writing to
  # the wrong day with nothing at either end saying so.
  test "a date that will not parse is refused rather than read as today" do
    get api_v1_nutrition_path, params: { date: "yesterday" }, headers: auth, as: :json

    assert_response :bad_request
  end

  test "the one-tap list is ranked by how often a food is logged, at the portion last used" do
    3.times { |i| log(@oats, grams: 80, at: i.hours.ago) }
    log(@whey, grams: 30)

    get api_v1_nutrition_path, headers: auth, as: :json

    suggestions = response.parsed_body.dig("data", "frequent_foods")
    assert_equal [ "Zzz Api Oats", "Zzz Api Whey" ], suggestions.map { |s| s.dig("food", "name") }
    assert_equal 80.0, suggestions.first.fetch("quantity_grams")
    assert_equal 3, suggestions.first.fetch("times_logged")
  end

  test "the day names the meal happening now, so a tap files itself correctly" do
    travel_to Time.utc(2026, 6, 11, 20, 30) do
      get api_v1_nutrition_path, headers: auth, as: :json

      assert_equal "dinner", response.parsed_body.dig("data", "current_meal_type")
    end
  end

  test "another account's log is not in this one's day" do
    users(:two).food_log_entries.create!(
      food: @oats, logged_at: Time.current, meal_type: "lunch", quantity_grams: 100,
      source: "manual", **@oats.macros_for(100)
    )

    get api_v1_nutrition_path, headers: auth, as: :json

    assert_equal 0, response.parsed_body.dig("data", "entries").length
  end

  # ---- logging ----------------------------------------------------------

  # The client says what and how much; the server says what that is worth. Taking
  # both from the client would let a portion and its macros disagree, and the
  # entry is the evidence a nutrition decision is built from.
  test "the macros are computed from the food and the portion, not taken from the caller" do
    post api_v1_food_log_entries_path, headers: auth, as: :json, params: {
      food_log_entry: { food_id: @oats.id, quantity_grams: 200, kcal: 1, protein_g: 1 }
    }

    assert_response :created
    entry = response.parsed_body.fetch("data")
    assert_equal 760.0, entry.fetch("kcal")
    assert_equal 26.0, entry.fetch("protein_g")
    assert_equal 760.0, FoodLogEntry.order(:id).last.kcal.to_f
  end

  # The column defaults to "snack", so leaving the key out entirely would file a
  # 9pm entry correctly by luck and an 8am one wrongly.
  test "an entry with no meal type is filed under the meal happening now" do
    travel_to Time.utc(2026, 6, 11, 8, 15) do
      post_entry(@oats, grams: 100)

      assert_response :created
      assert_equal "breakfast", response.parsed_body.dig("data", "meal_type")
    end
  end

  test "logging recomputes the day and comes back without waiting for it" do
    assert_enqueued_with(job: NutritionRecomputeJob, args: [ @user, @user.local_date ]) do
      post_entry(@oats, grams: 100)
    end

    assert_response :created
  end

  test "correcting a portion rescales the macros" do
    entry = log(@oats, grams: 100)

    patch api_v1_food_log_entry_path(entry), headers: auth, as: :json,
      params: { food_log_entry: { quantity_grams: 50 } }

    assert_response :success
    assert_equal 190.0, response.parsed_body.dig("data", "kcal")
    assert_equal 190.0, entry.reload.kcal.to_f
  end

  test "correcting only the meal leaves the portion and its macros alone" do
    entry = log(@oats, grams: 100)

    patch api_v1_food_log_entry_path(entry), headers: auth, as: :json,
      params: { food_log_entry: { meal_type: "dinner" } }

    assert_response :success
    assert_equal "dinner", entry.reload.meal_type
    assert_equal 380.0, entry.kcal.to_f
  end

  # A backdated entry belongs to the day it was eaten on, so that is the day
  # whose plan has to be recomposed — not today's.
  test "removing a backdated entry recomputes the day it was on" do
    entry = log(@oats, grams: 100, at: 3.days.ago)
    its_day = @user.local_date_at(entry.logged_at)

    assert_enqueued_with(job: NutritionRecomputeJob, args: [ @user, its_day ]) do
      delete api_v1_food_log_entry_path(entry), headers: auth, as: :json
    end

    assert_response :no_content
  end

  test "another account's entry is a 404 to read, correct or remove" do
    theirs = users(:two).food_log_entries.create!(
      food: @oats, logged_at: Time.current, meal_type: "lunch", quantity_grams: 100,
      source: "manual", **@oats.macros_for(100)
    )

    patch api_v1_food_log_entry_path(theirs), headers: auth, as: :json,
      params: { food_log_entry: { quantity_grams: 1 } }
    assert_response :not_found

    delete api_v1_food_log_entry_path(theirs), headers: auth, as: :json
    assert_response :not_found
    assert theirs.reload.persisted?
  end

  test "a food this account cannot see cannot be logged against it" do
    theirs = users(:two).foods.create!(
      name: "Zzz Api Theirs", serving_grams: 100, kcal: 10, protein_g: 1, carb_g: 1, fat_g: 1
    )

    assert_no_difference "FoodLogEntry.count" do
      post api_v1_food_log_entries_path, headers: auth, as: :json,
        params: { food_log_entry: { food_id: theirs.id, quantity_grams: 100 } }
    end

    assert_response :not_found
  end

  test "copying yesterday brings it forward once, however many times it is tapped" do
    log(@oats, grams: 80, at: 1.day.ago)
    log(@whey, grams: 30, at: 1.day.ago)

    assert_difference "FoodLogEntry.count", 2 do
      post copy_yesterday_api_v1_food_log_entries_path, headers: auth, as: :json
    end
    assert_equal 2, response.parsed_body.fetch("data").length
    assert_equal 2, response.parsed_body.dig("meta", "source_count")

    assert_no_difference "FoodLogEntry.count" do
      post copy_yesterday_api_v1_food_log_entries_path, headers: auth, as: :json
    end
    assert_equal 0, response.parsed_body.fetch("data").length
  end

  # ---- meals ------------------------------------------------------------

  test "a meal carries totals computed from its foods rather than a stored copy" do
    meal_for(@user, "Zzz Api Breakfast")

    get api_v1_meals_path, headers: auth, as: :json

    assert_response :success
    meal = response.parsed_body.fetch("data").find { |m| m.fetch("name") == "Zzz Api Breakfast" }
    assert_equal [ "Zzz Api Oats", "Zzz Api Whey" ], meal.fetch("items").map { |i| i.dig("food", "name") }
    # 80 g oats + 30 g whey.
    assert_in_delta 424.0, meal.dig("totals", "kcal"), 0.5
  end

  test "one tap logs every food in the meal, recorded as having arrived as one" do
    meal = meal_for(@user, "Zzz Api Tapped")

    assert_difference "FoodLogEntry.count", 2 do
      post log_api_v1_meal_path(meal), headers: auth, as: :json
    end

    assert_response :created
    assert_equal [ "meal" ], response.parsed_body.fetch("data").map { |e| e.fetch("source") }.uniq
  end

  test "another account's meal is a 404" do
    theirs = meal_for(users(:two), "Zzz Api Not Mine")

    post log_api_v1_meal_path(theirs), headers: auth, as: :json

    assert_response :not_found
  end

  # ---- finding something to log -----------------------------------------

  test "the catalog is searchable by name and by brand, and pages" do
    @user.foods.create!(name: "Zzz Api Skyr", brand: "Zzz Api Arla", serving_grams: 100,
      kcal: 63, protein_g: 11, carb_g: 4, fat_g: 0)

    get api_v1_foods_path, params: { q: "Zzz Api Arla" }, headers: auth, as: :json

    assert_response :success
    assert_equal [ "Zzz Api Skyr" ], response.parsed_body.fetch("data").pluck("name")

    get api_v1_foods_path, params: { q: "Zzz Api", limit: 1 }, headers: auth, as: :json
    assert_equal 1, response.parsed_body.fetch("data").length
    assert_equal 1, response.parsed_body.dig("meta", "next_offset")
  end

  test "the catalog holds the shared rows and this account's, and nobody else's" do
    shared = Food.find_or_create_by!(name: "Zzz Api Shared Apple") do |f|
      f.serving_grams = 100
      f.kcal = 52
      f.protein_g = 0
      f.carb_g = 14
      f.fat_g = 0
    end
    theirs = users(:two).foods.create!(name: "Zzz Api Secret", serving_grams: 100,
      kcal: 1, protein_g: 1, carb_g: 1, fat_g: 1)

    get api_v1_foods_path, params: { q: "Zzz Api" }, headers: auth, as: :json

    ids = response.parsed_body.fetch("data").pluck("id")
    assert_includes ids, shared.id
    assert_includes ids, @oats.id
    assert_not_includes ids, theirs.id
    assert_equal false, response.parsed_body.fetch("data").find { |f| f.fetch("id") == shared.id }.fetch("custom")
  end

  test "the database search maps results without writing anything" do
    stub_food_search

    assert_no_difference "Food.count" do
      get search_api_v1_foods_path, params: { q: "yogurt" }, headers: auth, as: :json
    end

    assert_response :success
    result = response.parsed_body.fetch("data").sole
    assert_equal "Greek Yogurt", result.fetch("name")
    assert_equal "1", result.fetch("barcode")
  end

  # Each call spends an outbound request, and the web rule keys on a path this
  # endpoint never matches. Keying on the device rather than the network means a
  # gym's shared address does not make one phone's typing count against another's.
  test "the database search is throttled per device, not per network" do
    stub_food_search
    other = sign_in_natively

    travel_to Time.utc(2026, 6, 11, 12, 0) do
      Rack::Attack::FOOD_SEARCH_LIMIT.times do |i|
        get search_api_v1_foods_path, params: { q: "yogurt#{i}" }, headers: auth, as: :json
        assert_response :success
      end

      get search_api_v1_foods_path, params: { q: "over" }, headers: auth, as: :json
      assert_response :too_many_requests

      get search_api_v1_foods_path, params: { q: "yogurt" }, headers: auth(other), as: :json
      assert_response :success, "a second device has its own budget"
    end
  end

  test "adding a searched food makes it loggable, and adding it twice finds the first" do
    assert_difference "Food.count", 1 do
      post api_v1_foods_path, headers: auth, as: :json, params: {
        food: { name: "Zzz Api Yogurt", brand: "Zzz Api Fage", barcode: "1234567890",
                serving_grams: 100, kcal: 59, protein_g: 10.3, carb_g: 3.6, fat_g: 0.4 }
      }
    end

    assert_response :created
    food = Food.order(:id).last
    assert_equal @user, food.user
    # Scanned off a packet rather than typed in, which is worth recording.
    assert_equal "barcode", food.source

    assert_no_difference "Food.count" do
      post api_v1_foods_path, headers: auth, as: :json, params: {
        food: { name: "Zzz Api Yogurt", brand: "Zzz Api Fage",
                serving_grams: 100, kcal: 59, protein_g: 10.3, carb_g: 3.6, fat_g: 0.4 }
      }
    end
    assert_response :success
    assert_equal food.id, response.parsed_body.dig("data", "id")
  end

  test "a food with impossible numbers is refused with its reasons" do
    assert_no_difference "Food.count" do
      post api_v1_foods_path, headers: auth, as: :json,
        params: { food: { name: "Zzz Api Bad", serving_grams: 0, kcal: -1, protein_g: 0, carb_g: 0, fat_g: 0 } }
    end

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("details").any?
  end

  # ---- the check-in -----------------------------------------------------

  # The one rule this endpoint exists to keep. Yesterday's answers describe
  # yesterday; carrying them over would make "save without reading" record a day
  # that was never answered.
  test "the check-in starts empty even when yesterday was answered in full" do
    check_in(@user.local_date - 1, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1)

    get api_v1_readiness_check_in_path, headers: auth, as: :json

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal false, data.fetch("checked_in")
    assert_equal({ "sleep_quality" => nil, "soreness" => nil, "fatigue" => nil, "stress" => nil },
      data.fetch("ratings"))
    assert_nil data.fetch("sleep_hours")
  end

  # Sleep hours is the one thing that does prefill, because the watch measured
  # it rather than guessing it.
  test "a night the watch measured comes back known, with the ratings still empty" do
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date, sleep_minutes: 447, resting_hr: 52, source: "healthkit"
    )

    get api_v1_readiness_check_in_path, headers: auth, as: :json

    data = response.parsed_body.fetch("data")
    assert_equal 7.45, data.fetch("sleep_hours")
    assert_equal true, data.fetch("sleep_from_watch")
    assert_equal 52, data.dig("objective", "resting_hr")
    assert_equal false, data.fetch("checked_in")
    assert data.fetch("ratings").values.all?(&:nil?), "the watch does not answer for the user"
  end

  # Without this a native client could post an empty body and have the day
  # scored from nothing — the same failure as materialising a check-in from a day
  # that only synced steps. The web form's `required` attributes are what stop it
  # there, and they do not reach this far.
  test "a check-in missing any rating is refused and writes nothing" do
    DailyReadinessInput::SUBJECTIVE_FIELDS.each do |omitted|
      answers = { sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2 }.except(omitted)

      assert_no_difference "DailyReadinessInput.count" do
        assert_no_enqueued_jobs only: ReadinessRecomputeJob do
          post api_v1_readiness_check_in_path, headers: auth, as: :json,
            params: { daily_readiness_input: answers }
        end
      end

      assert_response :unprocessable_entity, "#{omitted} missing should be refused"
      assert_match(/#{omitted.to_s.humanize}/, response.parsed_body.fetch("details").join(" "))
    end
  end

  test "a complete check-in is saved and queues the engine" do
    assert_difference "DailyReadinessInput.count", 1 do
      assert_enqueued_with(job: ReadinessRecomputeJob) do
        post api_v1_readiness_check_in_path, headers: auth, as: :json, params: {
          daily_readiness_input: { sleep_hours: 7.5, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
        }
      end
    end

    assert_response :created
    data = response.parsed_body.fetch("data")
    assert_equal true, data.fetch("checked_in")
    assert_equal 7.5, data.fetch("sleep_hours")
    assert_equal 4, data.dig("ratings", "sleep_quality")
    assert_equal 450, @user.daily_readiness_inputs.sole.sleep_minutes
  end

  test "checking in again the same day updates the day rather than failing on it" do
    post api_v1_readiness_check_in_path, headers: auth, as: :json, params: {
      daily_readiness_input: { sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
    }

    assert_difference "DailyReadinessInput.count", 0 do
      post api_v1_readiness_check_in_path, headers: auth, as: :json, params: {
        daily_readiness_input: { sleep_quality: 2, soreness: 4, fatigue: 4, stress: 4 }
      }
    end

    assert_response :created
    assert_equal 2, @user.daily_readiness_inputs.sole.sleep_quality
  end

  # The watch's measurement is evidence. A check-in that never mentioned sleep
  # must not erase it to record an absence.
  test "a check-in that says nothing about sleep leaves what the watch measured" do
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date, sleep_minutes: 447, source: "healthkit"
    )

    post api_v1_readiness_check_in_path, headers: auth, as: :json, params: {
      daily_readiness_input: { sleep_hours: "", sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
    }

    assert_response :created
    assert_equal 447, @user.daily_readiness_inputs.sole.sleep_minutes
    # Subjective answers on top of a watch-sourced row is exactly "mixed".
    assert_equal "mixed", @user.daily_readiness_inputs.sole.source
  end

  test "the score and the verdict are readable once the engine has run" do
    perform_enqueued_jobs do
      post api_v1_readiness_check_in_path, headers: auth, as: :json, params: {
        daily_readiness_input: { sleep_hours: 8, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1 }
      }
    end

    get api_v1_readiness_check_in_path, headers: auth, as: :json

    data = response.parsed_body.fetch("data")
    assert data.dig("score", "value").positive?
    assert_equal "daily_readiness", data.dig("decision", "decision_type")
    assert data.dig("decision", "output", "headline").present?
  end

  test "another account's check-in is not this one's" do
    users(:two).daily_readiness_inputs.create!(
      metric_date: users(:two).local_date, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1, source: "manual"
    )

    get api_v1_readiness_check_in_path, headers: auth, as: :json

    assert_equal false, response.parsed_body.dig("data", "checked_in")
  end

  # ---- the token still decides ------------------------------------------

  test "every nutrition and readiness endpoint refuses an unauthenticated request" do
    [ api_v1_nutrition_path, api_v1_foods_path, search_api_v1_foods_path,
      api_v1_meals_path, api_v1_readiness_check_in_path ].each do |path|
      get path, as: :json
      assert_response :unauthorized, "#{path} must require a token"
    end

    post api_v1_food_log_entries_path, as: :json, params: { food_log_entry: { food_id: @oats.id, quantity_grams: 1 } }
    assert_response :unauthorized

    post api_v1_readiness_check_in_path, as: :json,
      params: { daily_readiness_input: { sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2 } }
    assert_response :unauthorized
  end

  private

  def sign_in_natively
    post api_v1_session_path, params: { email_address: @user.email_address, password: "password" }, as: :json
    response.parsed_body.fetch("token")
  end

  def auth(token = @token)
    { "Authorization" => "Bearer #{token}" }
  end

  def food(name, **macros)
    @user.foods.create!(name: name, serving_grams: 100, **macros)
  end

  def log(item, grams:, at: Time.current)
    @user.food_log_entries.create!(
      food: item, logged_at: at, quantity_grams: grams, source: "manual", **item.macros_for(grams)
    )
  end

  def post_entry(item, grams:)
    post api_v1_food_log_entries_path, headers: auth, as: :json,
      params: { food_log_entry: { food_id: item.id, quantity_grams: grams } }
  end

  def meal_for(owner, name)
    foods = owner == @user ? [ @oats, @whey ] : catalog_pair
    meal = owner.meals.new(name: name)
    foods.each_with_index do |item, index|
      meal.meal_items.build(food: item, quantity_grams: 80 - (index * 50), position: index + 1)
    end
    meal.save!
    meal
  end

  def catalog_pair
    2.times.map do
      Food.create!(name: "Zzz Api Catalog #{SecureRandom.hex(3)}", serving_grams: 100,
        kcal: 100, protein_g: 5, carb_g: 10, fat_g: 2)
    end
  end

  def check_in(on, **answers)
    @user.daily_readiness_inputs.create!(metric_date: on, source: "manual", **answers)
  end

  def stub_food_search
    body = {
      "products" => [
        {
          "code" => "1", "product_name" => "Greek Yogurt", "brands" => "Fage",
          "nutriments" => { "energy-kcal_100g" => 59, "proteins_100g" => 10, "carbohydrates_100g" => 4, "fat_100g" => 0 }
        }
      ]
    }.to_json
    stub_request(:get, %r{world\.openfoodfacts\.org/cgi/search\.pl}).to_return(status: 200, body: body)
  end
end
