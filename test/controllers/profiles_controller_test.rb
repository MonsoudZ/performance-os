require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "edit renders the training profile form" do
    get edit_profile_path
    assert_response :success
    assert_select "form[action=?]", profile_path
  end

  test "update persists training profile fields" do
    patch profile_path, params: {
      user: {
        experience_level: "advanced",
        training_days_per_week: 5,
        available_equipment: [ "barbell", "dumbbell", "" ]
      }
    }

    assert_redirected_to edit_profile_path
    @user.reload
    assert_equal "advanced", @user.experience_level
    assert_equal 5, @user.training_days_per_week
    assert_equal %w[barbell dumbbell], @user.available_equipment # blank stripped
  end

  test "rejects clearing all equipment" do
    patch profile_path, params: { user: { available_equipment: [ "" ] } }

    assert_equal %w[barbell dumbbell machine bodyweight cable other], @user.reload.available_equipment
    assert_match(/equipment/i, flash[:alert])
  end

  test "still accepts the inline max-hr update" do
    patch profile_path, params: { user: { max_hr: 188 } }
    assert_equal 188, @user.reload.max_hr
  end
  test "saving the profile with no sex selected succeeds" do
    # The select offers "Prefer not to say", which posts "". The column's check
    # constraint takes NULL but not "", so this used to fail at the database and
    # silently discard every other field on the form — including unit_system.
    patch profile_path, params: { user: { sex: "", unit_system: "imperial" } }

    @user.reload

    assert_nil @user.sex
    assert_equal "imperial", @user.unit_system
  end

  test "rejects an unrecognized sex as a validation error, not a database error" do
    assert_nothing_raised do
      patch profile_path, params: { user: { sex: "wombat" } }
    end

    assert_not_equal "wombat", @user.reload.sex
  end

  test "the profile page lists where the account is signed in" do
    phone = @user.sessions.create!(
      user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1",
      ip_address: "203.0.113.7"
    )

    get edit_profile_path

    assert_response :success
    assert_select ".session-list__item", count: 2
    assert_select ".session-list__device", text: /Safari on iPhone/
    assert_select ".session-list__meta", text: /203\.0\.113\.7/
    # The device asking is marked, so "sign out everywhere else" is unambiguous.
    assert_select ".session-list__device .step", { text: "This device", count: 1 },
      "the current session should be the only one labelled"
    assert_select "form[action=?][method=post]", active_session_path(phone)
    assert_select "form[action=?]", other_active_sessions_path
  end

  # A session that expired since the nightly sweep is already dead, so listing
  # it would offer the user a device they cannot actually sign out of.
  test "the signed-in list leaves out sessions that have already expired" do
    stale = @user.sessions.create!(user_agent: "curl/8.4.0")
    stale.update_column(:last_active_at, Session::IDLE_TIMEOUT.ago - 1.day)

    get edit_profile_path

    assert_response :success
    assert_select ".session-list__item", count: 1
    assert_select ".session-list__device", { text: /curl/, count: 0 }
  end

  test "the only device signed in is not offered a sign-out-everywhere-else button" do
    get edit_profile_path

    assert_response :success
    assert_select ".session-list__item", count: 1
    assert_select "form[action=?]", other_active_sessions_path, count: 0
  end

  test "the profile page offers account deletion behind a password" do
    get edit_profile_path

    assert_response :success
    assert_select "form[action=?][method=post] input[name=password][type=password]", profile_path
    assert_select ".panel--danger", text: /cannot be undone/
  end

  test "deleting the account erases it and signs the user out" do
    @user.workout_sessions.create!(performed_at: 1.day.ago)

    assert_difference "User.count", -1 do
      delete profile_path, params: { password: "password" }
    end

    assert_redirected_to new_session_path
    assert_nil User.find_by(id: @user.id)
    assert_equal 0, WorkoutSession.where(user_id: @user.id).count
  end

  test "the deleted account's session cookie stops working" do
    delete profile_path, params: { password: "password" }

    # The session rows went with the account; a cookie still pointing at one
    # would try to resume a session that no longer exists.
    get edit_profile_path
    assert_redirected_to new_session_path
  end

  test "a wrong password deletes nothing" do
    assert_no_difference "User.count" do
      delete profile_path, params: { password: "not-the-password" }
    end

    assert_redirected_to edit_profile_path
    assert_match(/nothing was deleted/, flash[:alert])
    assert User.exists?(@user.id)
  end

  test "a missing password deletes nothing" do
    assert_no_difference "User.count" do
      delete profile_path
    end

    assert User.exists?(@user.id)
  end

  test "signing out closes account deletion too" do
    sign_out

    assert_no_difference "User.count" do
      delete profile_path, params: { password: "password" }
    end

    assert_redirected_to new_session_path
  end

  test "deleting one account leaves another alone" do
    other = users(:two)
    other.workout_sessions.create!(performed_at: 1.day.ago)

    delete profile_path, params: { password: "password" }

    assert User.exists?(other.id)
    assert_equal 1, WorkoutSession.where(user_id: other.id).count
  end
end
