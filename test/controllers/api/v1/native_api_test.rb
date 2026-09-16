require "test_helper"

# The native client's whole surface, driven the way the phone drives it: sign
# in, read the plan, log a workout, sign out.
#
# The thing worth guarding hardest is the token. It names a Session row, so it
# has to die with that row — on both of the session's clocks, and the moment the
# user ends that device from the signed-in list.
class Api::V1::NativeApiTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.reset!
    @user = users(:one)
    @squat = Exercise.find_or_create_by!(name: "Zzz Api Squat") { |e| e.modality = "barbell" }
    @curl = Exercise.find_or_create_by!(name: "Zzz Api Curl") { |e| e.modality = "dumbbell" }
  end

  teardown { Rack::Attack.reset! }

  # ---- signing in -------------------------------------------------------

  test "signing in returns a token and creates a device the web can see" do
    assert_difference "@user.sessions.count", 1 do
      post api_v1_session_path, params: { email_address: @user.email_address, password: "password" }, as: :json
    end

    assert_response :created
    body = response.parsed_body
    assert_match Session::API_TOKEN_PATTERN, body.fetch("token")
    assert_equal @user.id, body.dig("user", "id")
    # The same row backs /profile/edit, so the phone is listed with the laptop.
    assert_equal @user.sessions.order(:id).last.id, body.dig("session", "id")
  end

  test "the token is returned once and only its digest is kept" do
    token = sign_in_natively

    session = @user.sessions.order(:id).last
    assert_not_equal token, session.api_token_digest
    assert_equal Digest::SHA256.hexdigest(token), session.api_token_digest
  end

  test "a wrong password gets no token and creates no session" do
    assert_no_difference "@user.sessions.count" do
      post api_v1_session_path, params: { email_address: @user.email_address, password: "wrong" }, as: :json
    end

    assert_response :unauthorized
    assert_nil response.parsed_body["token"]
  end

  test "signing in is throttled by IP like the web form is" do
    Rack::Attack::LOGIN_LIMIT.times do
      post api_v1_session_path, params: { email_address: @user.email_address, password: "wrong" },
        headers: throttle_headers, as: :json
      assert_response :unauthorized
    end

    post api_v1_session_path, params: { email_address: @user.email_address, password: "password" },
      headers: throttle_headers, as: :json

    assert_response :too_many_requests
  end

  # ---- what the token is worth ------------------------------------------

  test "no token, a malformed one and a made-up one are all unauthorized" do
    [ nil, "Bearer nonsense", "Bearer pos_#{'a' * 43}" ].each do |header|
      get api_v1_profile_path, headers: header ? { "Authorization" => header } : {}, as: :json
      assert_response :unauthorized, "#{header.inspect} should not authenticate"
    end
  end

  # The point of tying the token to the session rather than giving it a clock of
  # its own: one row, one lifetime, and the list at /profile/edit really does
  # end the device.
  test "ending the device from the signed-in list kills its token" do
    token = sign_in_natively
    get api_v1_profile_path, headers: auth(token), as: :json
    assert_response :success

    @user.sessions.order(:id).last.destroy!

    get api_v1_profile_path, headers: auth(token), as: :json
    assert_response :unauthorized
  end

  test "a session idle past its timeout stops authenticating" do
    token = sign_in_natively
    @user.sessions.order(:id).last.update_column(:last_active_at, Session::IDLE_TIMEOUT.ago - 1.day)

    get api_v1_profile_path, headers: auth(token), as: :json

    assert_response :unauthorized
  end

  test "a session past its absolute lifetime stops authenticating even if used daily" do
    token = sign_in_natively
    @user.sessions.order(:id).last.update_columns(
      created_at: Session::ABSOLUTE_LIFETIME.ago - 1.day, last_active_at: Time.current
    )

    get api_v1_profile_path, headers: auth(token), as: :json

    assert_response :unauthorized
  end

  test "signing out destroys the session rather than blanking the token" do
    token = sign_in_natively

    assert_difference "@user.sessions.count", -1 do
      delete api_v1_session_path, headers: auth(token), as: :json
    end

    assert_response :no_content
    get api_v1_profile_path, headers: auth(token), as: :json
    assert_response :unauthorized
  end

  test "signing in again replaces the first token rather than leaving two live" do
    first = sign_in_natively
    session = @user.sessions.order(:id).last
    second = session.issue_api_token!

    get api_v1_profile_path, headers: auth(first), as: :json
    assert_response :unauthorized

    get api_v1_profile_path, headers: auth(second), as: :json
    assert_response :success
  end

  # ---- the profile ------------------------------------------------------

  test "the profile carries no credentials and says which units the client should render" do
    get api_v1_profile_path, headers: auth(sign_in_natively), as: :json

    assert_response :success
    user = response.parsed_body.fetch("user")
    assert_equal @user.unit_system, user.fetch("unit_system")
    assert_equal @user.time_zone, user.fetch("time_zone")
    %w[password_digest password pending_email_address].each do |secret|
      assert_not response.body.include?(secret), "#{secret} must not cross this boundary"
    end
  end

  # ---- workouts ---------------------------------------------------------

  test "a workout carries its lifts in order, with the targets in force today" do
    prescribe(@squat, working_sets: 3)
    template = build_template("Zzz Api Lower", [ @squat, @curl ])

    get api_v1_workout_templates_path, headers: auth(sign_in_natively), as: :json

    assert_response :success
    workout = response.parsed_body.fetch("data").find { |t| t.fetch("id") == template.id }
    assert_equal [ 1, 2 ], workout.fetch("exercises").pluck("position")

    squat, curl = workout.fetch("exercises")
    assert_equal 3, squat.dig("targets", "working_sets")
    assert_equal false, squat.fetch("uncovered")

    # The lift with no target still ships, and says so — the progression engine
    # will not evaluate it, and the client should be able to tell the user.
    assert_nil curl.fetch("targets")
    assert_equal true, curl.fetch("uncovered")
  end

  test "another account's workout is a 404, not a 403" do
    theirs = users(:two).workout_templates.create!(
      name: "Zzz Api Theirs", weekdays: [ 1 ],
      workout_template_exercises_attributes: [ { exercise_id: @squat.id, position: 1 } ]
    )

    get api_v1_workout_template_path(theirs), headers: auth(sign_in_natively), as: :json

    assert_response :not_found
  end

  test "logging a workout stores the sets and queues the progression engine" do
    prescribe(@squat, working_sets: 2)
    token = sign_in_natively

    assert_difference "WorkoutSession.count", 1 do
      assert_enqueued_with(job: WorkoutProgressionRecomputeJob) do
        post api_v1_workout_sessions_path, headers: auth(token), as: :json, params: {
          workout_session: {
            performed_at: Time.current.iso8601,
            session_rpe: 8,
            set_entries_attributes: [
              { exercise_id: @squat.id, set_index: 1, weight_kg: 100, reps: 8, rir: 1 },
              { exercise_id: @squat.id, set_index: 2, weight_kg: 100, reps: 8, rir: 1 }
            ]
          }
        }
      end
    end

    assert_response :created
    sets = response.parsed_body.dig("data", "sets")
    assert_equal [ 1, 2 ], sets.pluck("set_index")
    assert_equal [ 100.0, 100.0 ], sets.pluck("weight_kg")
  end

  # set_index restarts per lift, so a session sorted by it alone interleaves.
  test "a logged session comes back grouped by lift rather than interleaved" do
    token = sign_in_natively
    session = @user.workout_sessions.create!(performed_at: Time.current)
    [ [ @squat, 1 ], [ @squat, 2 ], [ @curl, 1 ], [ @curl, 2 ] ].each do |exercise, index|
      session.set_entries.create!(exercise: exercise, set_index: index, weight_kg: 60, reps: 8, rir: 2)
    end

    get api_v1_workout_session_path(session), headers: auth(token), as: :json

    assert_response :success
    names = response.parsed_body.dig("data", "sets").map { |set| set.dig("exercise", "name") }
    assert_equal [ "Zzz Api Squat", "Zzz Api Squat", "Zzz Api Curl", "Zzz Api Curl" ], names
  end

  test "a workout with no sets is refused with its reasons" do
    post api_v1_workout_sessions_path, headers: auth(sign_in_natively), as: :json,
      params: { workout_session: { performed_at: nil } }

    assert_response :unprocessable_entity
    assert response.parsed_body.fetch("details").any?
  end

  # A native request is a record being transported, not a form being submitted,
  # so the number means kilograms whoever sent it. Running it through the web
  # form's converter read an imperial user's kilograms as pounds, and a round
  # trip through the phone turned 100 kg into 45.36.
  test "a weight crosses this boundary in kilograms whatever the user's units" do
    imperial = users(:two)
    assert_equal "imperial", imperial.unit_system
    post api_v1_session_path, params: { email_address: imperial.email_address, password: "password" }, as: :json
    token = response.parsed_body.fetch("token")

    # Deliberately the hash-of-index spelling: that is the one the converter
    # reached, so an array here would pass against the very bug this guards.
    post api_v1_workout_sessions_path, headers: auth(token), as: :json, params: {
      workout_session: {
        performed_at: Time.current.iso8601,
        set_entries_attributes: { "0" => { exercise_id: @squat.id, set_index: 1, weight_kg: 100, reps: 5, rir: 2 } }
      }
    }

    assert_response :created
    assert_equal 100.0, response.parsed_body.dig("data", "sets", 0, "weight_kg")
    assert_equal BigDecimal("100"), SetEntry.order(:id).last.weight_kg
  end

  # The converter's nested branch tests `respond_to?(:each_value)`, which an
  # array does not answer to, so it converted one spelling of the same payload
  # and silently skipped the other. Two clients sending the same workout stored
  # two different weights, and the array form — the one a JSON client reaches for
  # first — was the one that happened to look right.
  test "the same sets are stored the same way however the client spells them" do
    imperial = users(:two)
    post api_v1_session_path, params: { email_address: imperial.email_address, password: "password" }, as: :json
    token = response.parsed_body.fetch("token")
    set = { exercise_id: @squat.id, set_index: 1, weight_kg: 100, reps: 5, rir: 2 }

    stored = [ [ set ], { "0" => set } ].map do |spelling|
      post api_v1_workout_sessions_path, headers: auth(token), as: :json, params: {
        workout_session: { performed_at: Time.current.iso8601, set_entries_attributes: spelling }
      }
      assert_response :created
      SetEntry.order(:id).last.weight_kg
    end

    assert_equal [ BigDecimal("100"), BigDecimal("100") ], stored
  end

  # The snapshot is what freezes what a workout was asked for on the day it was
  # logged, so a later block change cannot rewrite it. The web built one in a
  # controller private method, so a session logged from the phone set the
  # foreign key and stored `{}` — and the API's own response said
  # `template_name: null` for a workout run from a named template.
  test "a workout run from a template records what it was asked for" do
    prescribe(@squat, working_sets: 4)
    template = build_template("Zzz Api Snapshot", [ @squat ])

    post api_v1_workout_sessions_path, headers: auth(sign_in_natively), as: :json, params: {
      workout_session: {
        performed_at: Time.current.iso8601,
        workout_template_id: template.id,
        set_entries_attributes: [ { exercise_id: @squat.id, set_index: 1, weight_kg: 100, reps: 5, rir: 2 } ]
      }
    }

    assert_response :created
    assert_equal "Zzz Api Snapshot", response.parsed_body.dig("data", "template_name")

    session = WorkoutSession.order(:id).last
    assert_equal template.id, session.workout_template_id
    assert_equal "Zzz Api Snapshot", session.template_snapshot.fetch("name")
    assert_equal 4, session.planned_working_sets
  end

  # The snapshot is a record of what was asked for *then*, so it resolves the
  # targets on the session's own date. Building it from today would let a
  # prescription changed since rewrite what a backdated workout was asked to do
  # — which is the one thing freezing it exists to prevent.
  test "a backdated workout records the targets that were in force that day" do
    @user.exercise_prescriptions.create!(
      exercise: @squat, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current - 30, ended_on: Date.current - 10
    )
    @user.exercise_prescriptions.create!(
      exercise: @squat, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 5, started_on: Date.current - 9
    )
    template = build_template("Zzz Api Backdated", [ @squat ])

    post api_v1_workout_sessions_path, headers: auth(sign_in_natively), as: :json, params: {
      workout_session: {
        performed_at: (Time.current - 20.days).iso8601,
        workout_template_id: template.id,
        set_entries_attributes: [ { exercise_id: @squat.id, set_index: 1, weight_kg: 100, reps: 7, rir: 2 } ]
      }
    }

    assert_response :created
    # Three, as prescribed twenty days ago — not the five prescribed since.
    assert_equal 3, WorkoutSession.order(:id).last.planned_working_sets
  end

  # The web looked its template up through the user's own; the API permitted the
  # id straight through and stored it, so a phone could point its workout at
  # somebody else's split.
  test "a workout cannot be pointed at another account's template" do
    theirs = users(:two).workout_templates.create!(
      name: "Zzz Api Not Mine", weekdays: [ 1 ],
      workout_template_exercises_attributes: [ { exercise_id: @squat.id, position: 1 } ]
    )

    post api_v1_workout_sessions_path, headers: auth(sign_in_natively), as: :json, params: {
      workout_session: {
        performed_at: Time.current.iso8601,
        workout_template_id: theirs.id,
        set_entries_attributes: [ { exercise_id: @squat.id, set_index: 1, weight_kg: 100, reps: 5, rir: 2 } ]
      }
    }

    assert_response :created
    assert_nil WorkoutSession.order(:id).last.workout_template_id
  end

  # The backstop, for any writer that reaches past the scoped lookup.
  test "a session holding another account's template is invalid" do
    theirs = users(:two).workout_templates.create!(
      name: "Zzz Api Also Not Mine", weekdays: [ 1 ],
      workout_template_exercises_attributes: [ { exercise_id: @squat.id, position: 1 } ]
    )
    session = @user.workout_sessions.new(performed_at: Time.current, workout_template: theirs)

    assert_not session.valid?
    assert_match(/not available/i, session.errors.full_messages.join(" "))
  end

  # Both spellings of nested attributes mean the same thing, so both have to be
  # converted or neither — the converter recognised only the hash form, so a
  # payload was or was not converted depending on how it was written.
  test "a metric user's weights survive both spellings of the same payload" do
    token = sign_in_natively
    set = { exercise_id: @squat.id, set_index: 1, weight_kg: 102.5, reps: 5, rir: 2 }

    stored = [ [ set ], { "0" => set } ].map do |spelling|
      post api_v1_workout_sessions_path, headers: auth(token), as: :json, params: {
        workout_session: { performed_at: Time.current.iso8601, set_entries_attributes: spelling }
      }
      assert_response :created
      SetEntry.order(:id).last.weight_kg
    end

    assert_equal [ BigDecimal("102.5"), BigDecimal("102.5") ], stored
  end

  test "every training endpoint refuses an unauthenticated request" do
    [ api_v1_profile_path, api_v1_workout_templates_path, api_v1_workout_sessions_path ].each do |path|
      get path, as: :json
      assert_response :unauthorized, "#{path} must require a token"
    end
  end

  private

  def sign_in_natively
    post api_v1_session_path, params: { email_address: @user.email_address, password: "password" }, as: :json
    response.parsed_body.fetch("token")
  end

  def auth(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def throttle_headers
    { "X-Forwarded-For" => "203.0.113.55, 10.0.0.9", "REMOTE_ADDR" => "10.0.0.9" }
  end

  def prescribe(exercise, working_sets: 3)
    @user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: working_sets, started_on: Date.current - 7
    )
  end

  def build_template(name, exercises)
    @user.workout_templates.create!(
      name: name, weekdays: [ 1 ],
      workout_template_exercises_attributes: exercises.each_with_index.map { |e, i|
        { exercise_id: e.id, position: i + 1 }
      }
    )
  end
end
