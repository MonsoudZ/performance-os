require "test_helper"

# Reading back the run of check-ins, and correcting one after its day.
#
# Correcting is a different question from answering — "what did I mean to put"
# rather than "how are you" — so a correction names what it is correcting and
# leaves the rest alone. The one thing it may not do is empty a rating: a day
# the user answered would go on being scored, from less than they actually know.
class Api::V1::NativeReadinessHistoryApiTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    @token = sign_in_natively
  end

  teardown { Rack::Attack.reset! }

  # ---- the history ------------------------------------------------------

  test "the run of check-ins comes back newest first" do
    3.times { |offset| check_in(@user.local_date - offset) }

    get api_v1_readiness_inputs_path, headers: auth, as: :json

    assert_response :success
    dates = response.parsed_body.fetch("data").pluck("date")
    assert_equal [ 0, 1, 2 ].map { |o| (@user.local_date - o).iso8601 }, dates
    assert response.parsed_body.fetch("data").all? { |day| day.fetch("checked_in") }
  end

  test "each day carries the score and the verdict the engine wrote for it" do
    perform_enqueued_jobs do
      post api_v1_readiness_check_in_path, headers: auth, as: :json, params: {
        daily_readiness_input: { sleep_hours: 8, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1 }
      }
    end

    get api_v1_readiness_inputs_path, headers: auth, as: :json

    today = response.parsed_body.fetch("data").sole
    assert today.dig("score", "value").positive?
    assert_equal "daily_readiness", today.dig("decision", "decision_type")
    assert today.dig("decision", "output", "headline").present?
  end

  test "a withdrawn verdict is not the one the history reports" do
    perform_enqueued_jobs do
      post api_v1_readiness_check_in_path, headers: auth, as: :json, params: {
        daily_readiness_input: { sleep_hours: 8, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1 }
      }
    end
    @user.coaching_decisions.of_type("daily_readiness").last.retract!(reason: "test")

    get api_v1_readiness_inputs_path, headers: auth, as: :json

    assert_nil response.parsed_body.fetch("data").sole.fetch("decision")
  end

  # A day the watch synced but nobody answered is still part of the run — it is
  # what the objective baselines are built from — and it says plainly that it
  # was not answered rather than being left out or being counted as one.
  test "a day the watch synced but nobody answered is listed as unanswered" do
    @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date - 1, sleep_minutes: 447, resting_hr: 52, source: "healthkit"
    )

    get api_v1_readiness_inputs_path, headers: auth, as: :json

    day = response.parsed_body.fetch("data").sole
    assert_equal false, day.fetch("checked_in")
    assert day.fetch("ratings").values.all?(&:nil?)
    assert_equal 7.45, day.fetch("sleep_hours")
    assert_equal true, day.fetch("sleep_from_watch")
    # Measured but unanswered: "mixed" would claim the user had a hand in it.
    assert_equal "healthkit", day.fetch("source")
  end

  test "the window is capped however large a limit is asked for" do
    now = Time.current
    rows = (1..(Api::V1::ReadinessInputsController::MAX_LIMIT + 5)).map do |offset|
      { user_id: @user.id, metric_date: @user.local_date - offset, sleep_quality: 3,
        soreness: 3, fatigue: 3, stress: 3, source: "manual", created_at: now, updated_at: now }
    end
    DailyReadinessInput.insert_all!(rows)

    get api_v1_readiness_inputs_path, params: { limit: 5_000 }, headers: auth, as: :json

    assert_equal Api::V1::ReadinessInputsController::MAX_LIMIT,
      response.parsed_body.fetch("data").length
  end

  test "a limit of zero or less still answers with history" do
    check_in(@user.local_date)

    [ 0, -5 ].each do |limit|
      get api_v1_readiness_inputs_path, params: { limit: limit }, headers: auth, as: :json

      assert_response :success, "limit=#{limit} should be clamped, not obeyed"
      assert_equal 1, response.parsed_body.fetch("data").length
    end
  end

  test "another account's check-ins are not in this one's history" do
    users(:two).daily_readiness_inputs.create!(
      metric_date: Date.current, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1, source: "manual"
    )

    get api_v1_readiness_inputs_path, headers: auth, as: :json

    assert_equal 0, response.parsed_body.fetch("data").length
  end

  # ---- correcting one ---------------------------------------------------

  test "a correction changes what it names and re-scores the day" do
    input = check_in(@user.local_date - 2, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2)

    assert_enqueued_with(job: ReadinessRecomputeJob) do
      patch api_v1_readiness_input_path(input), headers: auth, as: :json,
        params: { daily_readiness_input: { soreness: 5 } }
    end

    assert_response :success
    input.reload
    assert_equal 5, input.soreness
    # The ratings the correction never mentioned are left as they were.
    assert_equal [ 4, 2, 2 ], [ input.sleep_quality, input.fatigue, input.stress ]
    assert_equal 5, response.parsed_body.dig("data", "ratings", "soreness")
  end

  # Unlike answering today's, a correction is not required to restate all four.
  test "a correction naming one rating is not refused for omitting the rest" do
    input = check_in(@user.local_date - 1)

    patch api_v1_readiness_input_path(input), headers: auth, as: :json,
      params: { daily_readiness_input: { stress: 1 } }

    assert_response :success
    assert_equal 1, input.reload.stress
  end

  # Blanking one leaves the day answered enough to be scored and less answered
  # than the user actually is.
  test "a rating the correction names may not be emptied" do
    input = check_in(@user.local_date - 1, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2)

    DailyReadinessInput::SUBJECTIVE_FIELDS.each do |field|
      assert_no_enqueued_jobs only: ReadinessRecomputeJob do
        patch api_v1_readiness_input_path(input), headers: auth, as: :json,
          params: { daily_readiness_input: { field => "" } }
      end

      assert_response :unprocessable_entity, "clearing #{field} should be refused"
      assert_match(/#{field.to_s.humanize}/, response.parsed_body.fetch("details").join(" "))
      assert_equal 2, input.reload.fatigue, "nothing should have been written"
    end
  end

  test "a rating outside the scale is refused with its reason" do
    input = check_in(@user.local_date - 1)

    patch api_v1_readiness_input_path(input), headers: auth, as: :json,
      params: { daily_readiness_input: { soreness: 9 } }

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("details").any?
  end

  # A night the watch measured is evidence; a correction that never mentioned
  # sleep must not erase it to record an absence.
  test "a correction that says nothing about sleep leaves what the watch measured" do
    input = @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date - 1, sleep_minutes: 447, resting_hr: 52, source: "healthkit"
    )

    patch api_v1_readiness_input_path(input), headers: auth, as: :json, params: {
      daily_readiness_input: { sleep_hours: "", sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
    }

    assert_response :success
    assert_equal 447, input.reload.sleep_minutes
  end

  # The rule three writers used to answer three ways.
  test "answering a watch-synced day through a correction makes it read as both" do
    input = @user.daily_readiness_inputs.create!(
      metric_date: @user.local_date - 1, sleep_minutes: 447, resting_hr: 52, source: "healthkit"
    )

    patch api_v1_readiness_input_path(input), headers: auth, as: :json, params: {
      daily_readiness_input: { sleep_quality: 4, soreness: 2, fatigue: 2, stress: 3 }
    }

    assert_response :success
    assert_equal "mixed", input.reload.source
    assert_equal "mixed", response.parsed_body.dig("data", "source")
    assert_equal true, response.parsed_body.dig("data", "checked_in")
  end

  test "a day nothing measured stays plainly manual when it is corrected" do
    input = check_in(@user.local_date - 1)

    patch api_v1_readiness_input_path(input), headers: auth, as: :json,
      params: { daily_readiness_input: { stress: 1 } }

    assert_equal "manual", input.reload.source
  end

  test "another account's check-in is a 404 to correct" do
    theirs = users(:two).daily_readiness_inputs.create!(
      metric_date: Date.current, sleep_quality: 5, soreness: 1, fatigue: 1, stress: 1, source: "manual"
    )

    patch api_v1_readiness_input_path(theirs), headers: auth, as: :json,
      params: { daily_readiness_input: { stress: 3 } }

    assert_response :not_found
    assert_equal 1, theirs.reload.stress
  end

  test "both endpoints refuse an unauthenticated request" do
    input = check_in(@user.local_date)

    get api_v1_readiness_inputs_path, as: :json
    assert_response :unauthorized

    patch api_v1_readiness_input_path(input), as: :json,
      params: { daily_readiness_input: { stress: 1 } }
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

  def check_in(on, sleep_quality: 3, soreness: 3, fatigue: 3, stress: 3)
    @user.daily_readiness_inputs.create!(
      metric_date: on, sleep_minutes: 420, source: "manual",
      sleep_quality: sleep_quality, soreness: soreness, fatigue: fatigue, stress: stress
    )
  end
end
