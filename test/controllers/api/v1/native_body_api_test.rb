require "test_helper"

# Weighing in from the phone.
#
# A weigh-in is the evidence behind the calorie target — it feeds the weight
# trend, the trend feeds the adaptive expenditure estimate, and that feeds the
# target — so the two things worth guarding are that the number arrives intact
# and that writing one recomputes the day it belongs to.
class Api::V1::NativeBodyApiTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @token = sign_in_as_native(@user)
  end

  teardown { Rack::Attack.reset! }

  # ---- reading the picture ----------------------------------------------

  test "the weigh-ins, the trend they make and the expenditure estimate come back together" do
    perform_enqueued_jobs do
      weigh_in(82.5, on: @user.local_date - 1)
      weigh_in(82.1, on: @user.local_date)
    end

    get api_v1_body_metrics_path, headers: auth, as: :json

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal [ 82.1, 82.5 ], data.fetch("metrics").pluck("weight_kg")
    assert_equal 2, data.fetch("trend").length
    # Nothing has estimated expenditure yet, and null is the honest answer.
    assert_nil data.fetch("expenditure")
  end

  # Every rule downstream reads the smoothed figure, never the raw one: a single
  # morning reading moves with water and yesterday's salt. A client drawing the
  # trend has to be able to tell the two apart.
  test "the trend carries the smoothed figure alongside what the scale said" do
    perform_enqueued_jobs do
      weigh_in(84.0, on: @user.local_date - 2)
      weigh_in(80.0, on: @user.local_date)
    end

    get api_v1_body_metrics_path, headers: auth, as: :json

    today = response.parsed_body.dig("data", "trend").find { |t| t.fetch("trend_date") == @user.local_date.iso8601 }
    assert_equal 80.0, today.fetch("raw_kg")
    assert_not_equal today.fetch("raw_kg"), today.fetch("ewma_kg"),
      "the smoothed figure is what the calorie target reads"
    assert_in_delta 83.0, today.fetch("ewma_kg"), 0.01
  end

  test "the estimate comes back once there is enough evidence behind it" do
    8.times do |offset|
      date = @user.local_date - offset
      @user.food_log_entries.create!(
        logged_at: @user.local_day_range(date).first + 12.hours, meal_type: "lunch",
        quantity_grams: 500, source: "manual", kcal: 2500, protein_g: 150, carb_g: 250, fat_g: 80
      )
      @user.weight_trends.create!(trend_date: date, raw_kg: 80, ewma_kg: 80)
    end
    ExpenditureEstimator.new(@user).call

    get api_v1_body_metrics_path, headers: auth, as: :json

    estimate = response.parsed_body.dig("data", "expenditure")
    assert estimate.fetch("estimated_tdee").positive?
    assert_includes %w[energy_balance wearable_energy], estimate.fetch("basis")
    assert_includes %w[low moderate high], estimate.fetch("confidence")
  end

  test "the window is capped however large a limit is asked for" do
    now = Time.current
    rows = (1..(Api::V1::BodyMetricsController::MAX_LIMIT + 5)).map do |offset|
      { user_id: @user.id, measured_on: @user.local_date - offset, weight_kg: 80,
        source: "manual", created_at: now, updated_at: now }
    end
    BodyMetric.insert_all!(rows)

    get api_v1_body_metrics_path, params: { limit: 5_000 }, headers: auth, as: :json

    assert_response :success
    assert_equal Api::V1::BodyMetricsController::MAX_LIMIT,
      response.parsed_body.dig("data", "metrics").length
  end

  # A limit of zero would otherwise report an empty history to a client that
  # only meant "I do not care how many", and a negative one is a query error.
  test "a limit of zero or less still answers with history" do
    perform_enqueued_jobs { weigh_in(82.4) }

    [ 0, -5 ].each do |limit|
      get api_v1_body_metrics_path, params: { limit: limit }, headers: auth, as: :json

      assert_response :success, "limit=#{limit} should be clamped, not obeyed"
      assert_equal 1, response.parsed_body.dig("data", "metrics").length
    end
  end

  test "another account's weigh-ins are not in this one's history" do
    users(:two).body_metrics.create!(measured_on: Date.current, weight_kg: 60, source: "manual")

    get api_v1_body_metrics_path, headers: auth, as: :json

    assert_equal 0, response.parsed_body.dig("data", "metrics").length
  end

  # ---- writing one ------------------------------------------------------

  test "a weigh-in is stored and recomputes the day it was measured on" do
    assert_difference "BodyMetric.count", 1 do
      assert_enqueued_with(job: BodyMetricRecomputeJob, args: [ @user, @user.local_date ]) do
        weigh_in(82.4)
      end
    end

    assert_response :created
    assert_equal 82.4, response.parsed_body.dig("data", "weight_kg")
  end

  # The column carries six decimal places so a re-save cannot silently change
  # what the user entered. Rounding to a display width here would hand that back.
  test "a weight is stored at the precision it arrived with" do
    weigh_in(82.456789)

    assert_equal 82.456789, response.parsed_body.dig("data", "weight_kg")
    assert_equal BigDecimal("82.456789"), BodyMetric.order(:id).last.weight_kg
  end

  # The rule for this whole boundary: a request is a record being transported,
  # so the number means kilograms whoever sent it. Running it through the web
  # form's converter would read an imperial user's kilograms as pounds.
  test "an imperial user's kilograms are stored as kilograms" do
    imperial = users(:two)
    assert_equal "imperial", imperial.unit_system
    token = sign_in_as_native(imperial)

    post api_v1_body_metrics_path, headers: auth(token), as: :json,
      params: { body_metric: { weight_kg: 100 } }

    assert_response :created
    assert_equal 100.0, response.parsed_body.dig("data", "weight_kg")
    assert_equal BigDecimal("100"), imperial.body_metrics.sole.weight_kg
  end

  test "a weigh-in with no date is filed on the user's own day, not UTC's" do
    travel_to Time.utc(2026, 6, 10, 5, 30) do
      weigh_in(82.4)
    end

    # 05:30 UTC is still the 9th in Denver.
    assert_equal Date.new(2026, 6, 9), BodyMetric.order(:id).last.measured_on
    assert_equal "2026-06-09", response.parsed_body.dig("data", "measured_on")
  end

  test "a backdated weigh-in recomputes the day it was measured on" do
    on = @user.local_date - 5

    assert_enqueued_with(job: BodyMetricRecomputeJob, args: [ @user, on ]) do
      weigh_in(82.4, on: on)
    end
  end

  # A row claiming "healthkit" is one the next sync overwrites: the materializer
  # finds its row by (date, source) and re-derives it. A weight somebody typed
  # has to be a row nothing else owns.
  test "a client cannot file a typed weight as one the watch derived" do
    weigh_in(82.4, extra: { source: "healthkit" })

    assert_response :created
    assert_equal "manual", BodyMetric.order(:id).last.source
    assert_equal false, response.parsed_body.dig("data", "derived")

    sync_body_mass(90.0, on: @user.local_date)

    weights = @user.body_metrics.order(:id).map { |m| [ m.source, m.weight_kg.to_f ] }
    assert_equal [ [ "manual", 82.4 ], [ "healthkit", 90.0 ] ], weights,
      "the sync writes its own row and leaves the typed one alone"
  end

  test "a weigh-in the watch derived says so" do
    sync_body_mass(90.0, on: @user.local_date)

    get api_v1_body_metrics_path, headers: auth, as: :json

    metric = response.parsed_body.dig("data", "metrics").sole
    assert_equal "healthkit", metric.fetch("source")
    assert_equal true, metric.fetch("derived")
  end

  test "an impossible weight is refused with its reasons" do
    assert_no_difference "BodyMetric.count" do
      weigh_in(0)
    end

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("details").any?
  end

  test "body fat crosses the boundary as the percentage it is" do
    weigh_in(82.4, extra: { body_fat_pct: 18.4 })

    assert_response :created
    assert_equal 18.4, response.parsed_body.dig("data", "body_fat_pct")
    assert_equal BigDecimal("18.4"), BodyMetric.order(:id).last.body_fat_pct
  end

  test "an impossible body fat percentage is refused with its reason" do
    assert_no_difference "BodyMetric.count" do
      weigh_in(82.4, extra: { body_fat_pct: 140 })
    end

    assert_response :unprocessable_entity
    assert_match(/body fat/i, response.parsed_body.fetch("details").join(" "))
  end

  # ---- removing one -----------------------------------------------------

  test "removing a backdated weigh-in recomputes the day it was on" do
    on = @user.local_date - 3
    perform_enqueued_jobs { weigh_in(82.4, on: on) }
    metric = @user.body_metrics.sole

    assert_enqueued_with(job: BodyMetricRecomputeJob, args: [ @user, on ]) do
      delete api_v1_body_metric_path(metric), headers: auth, as: :json
    end

    assert_response :no_content
    assert_equal 0, @user.body_metrics.count
  end

  # The EWMA is walked forward from the edited day, so removing a reading has to
  # leave the trend describing what is left rather than a stale row.
  test "removing the only weigh-in for a day drops its trend row too" do
    perform_enqueued_jobs { weigh_in(82.4) }
    assert_equal 1, @user.weight_trends.count

    perform_enqueued_jobs do
      delete api_v1_body_metric_path(@user.body_metrics.sole), headers: auth, as: :json
    end

    assert_equal 0, @user.weight_trends.count
  end

  test "another account's weigh-in is a 404" do
    theirs = users(:two).body_metrics.create!(measured_on: Date.current, weight_kg: 60, source: "manual")

    delete api_v1_body_metric_path(theirs), headers: auth, as: :json

    assert_response :not_found
    assert theirs.reload.persisted?
  end

  test "every body endpoint refuses an unauthenticated request" do
    get api_v1_body_metrics_path, as: :json
    assert_response :unauthorized

    post api_v1_body_metrics_path, as: :json, params: { body_metric: { weight_kg: 80 } }
    assert_response :unauthorized
  end

  private

  def sign_in_as_native(user)
    post api_v1_session_path, params: { email_address: user.email_address, password: "password" }, as: :json
    response.parsed_body.fetch("token")
  end

  def auth(token = @token)
    { "Authorization" => "Bearer #{token}" }
  end

  def weigh_in(weight_kg, on: nil, extra: {})
    attributes = { weight_kg: weight_kg }.merge(extra)
    attributes[:measured_on] = on.iso8601 if on

    post api_v1_body_metrics_path, headers: auth, as: :json, params: { body_metric: attributes }
  end

  def sync_body_mass(weight_kg, on:)
    device, = WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit",
      external_id: "zzz-api-scale-#{SecureRandom.hex(3)}", name: "Zzz Api Scale"
    )
    device.wearable_samples.create!(
      user: @user, external_id: "zzz-mass-#{SecureRandom.hex(4)}", metric_type: "body_mass_kg",
      started_at: @user.local_day_range(on).first + 7.hours,
      ended_at: @user.local_day_range(on).first + 7.hours,
      value: weight_kg, unit: WearableSample::METRIC_UNITS.fetch("body_mass_kg")
    )
    WearableBodyMassMaterializer.new(@user, metric_date: on).call
  end
end
