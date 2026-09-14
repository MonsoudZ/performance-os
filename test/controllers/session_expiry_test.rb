require "test_helper"

# What the clock on a session actually does to a request.
class SessionExpiryTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
    @session = Current.session
  end

  test "a session in use resumes normally" do
    get root_path

    assert_response :success
  end

  test "a session idle past the timeout is refused and its row deleted" do
    @session.update_column(:last_active_at, Session::IDLE_TIMEOUT.ago - 1.minute)

    get root_path

    assert_redirected_to new_session_path
    assert_not Session.exists?(@session.id), "the expired session should not be left looking live"
  end

  test "a session past the absolute lifetime is refused however recently it was used" do
    @session.update_columns(
      created_at: Session::ABSOLUTE_LIFETIME.ago - 1.minute,
      last_active_at: Time.current
    )

    get root_path

    assert_redirected_to new_session_path
    assert_not Session.exists?(@session.id)
  end

  # Without this the idle window never advances and every session dies thirty
  # days after it was created, however much it was used.
  test "a request advances the session's activity once it has gone stale" do
    stale = Session::ACTIVITY_PRECISION.ago - 1.minute
    @session.update_column(:last_active_at, stale)

    get root_path

    assert_response :success
    assert_operator @session.reload.last_active_at, :>, stale
  end

  test "a request within the precision window writes nothing" do
    before = @session.reload.last_active_at

    get root_path

    assert_response :success
    assert_equal before.to_i, @session.reload.last_active_at.to_i
  end
end
