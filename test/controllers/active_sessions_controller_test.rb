require "test_helper"

class ActiveSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @current = Current.session
    @phone = @user.sessions.create!(user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1")
  end

  test "signs out another device without disturbing this one" do
    assert_difference "@user.sessions.count", -1 do
      delete active_session_path(@phone)
    end

    assert_redirected_to edit_profile_path
    assert_not Session.exists?(@phone.id)

    # Still signed in here.
    get edit_profile_path
    assert_response :success
  end

  # Signing yourself out from the list is still signing out, so the cookie has
  # to go with the row or the next request resumes a session that is not there.
  test "signing out this device ends the session" do
    delete active_session_path(@current)

    assert_redirected_to new_session_path
    assert_not Session.exists?(@current.id)

    get edit_profile_path
    assert_redirected_to new_session_path
  end

  test "signs out every other device and keeps this one" do
    @user.sessions.create!
    assert_equal 3, @user.sessions.count

    delete other_active_sessions_path

    assert_redirected_to edit_profile_path
    assert_equal [ @current.id ], @user.sessions.reload.pluck(:id)

    get edit_profile_path
    assert_response :success
  end

  test "says so plainly when there is nothing else to sign out" do
    @phone.destroy

    delete other_active_sessions_path

    assert_match(/only device/, flash[:notice])
    assert_equal [ @current.id ], @user.sessions.reload.pluck(:id)
  end

  # Scoped to the signed-in user, so an id guessed from somebody else's account
  # revokes nothing.
  test "cannot sign out a session belonging to another account" do
    theirs = users(:two).sessions.create!

    assert_no_difference "Session.count" do
      delete active_session_path(theirs)
    end

    assert_response :not_found
    assert Session.exists?(theirs.id)
  end

  test "requires a signed-in user" do
    sign_out

    delete other_active_sessions_path
    assert_redirected_to new_session_path
  end
end
