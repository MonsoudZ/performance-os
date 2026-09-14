require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a session in use is not expired" do
    assert_not @user.sessions.create!.expired?
  end

  test "a session unused for longer than the idle timeout is expired" do
    session = aged(last_active_at: Session::IDLE_TIMEOUT.ago - 1.minute)

    assert session.expired?
    assert_includes Session.expired, session
    assert_not_includes Session.active, session
  end

  # The backstop idle expiry cannot reach: a cookie somebody is actively using
  # never goes idle, so age alone has to end it.
  test "a session in constant use still expires at the absolute lifetime" do
    session = aged(created_at: Session::ABSOLUTE_LIFETIME.ago - 1.minute, last_active_at: Time.current)

    assert session.expired?
    assert_includes Session.expired, session
    assert_not_includes Session.active, session
  end

  test "a session just inside both clocks is active" do
    session = aged(
      created_at: Session::ABSOLUTE_LIFETIME.ago + 1.hour,
      last_active_at: Session::IDLE_TIMEOUT.ago + 1.hour
    )

    assert_not session.expired?
    assert_includes Session.active, session
    assert_not_includes Session.expired, session
  end

  # active and expired have to be exact complements, or the sweep deletes a row
  # the request path would have honoured (or leaves one it would not).
  test "active and expired partition every session" do
    aged(last_active_at: Session::IDLE_TIMEOUT.ago - 1.day)
    aged(created_at: Session::ABSOLUTE_LIFETIME.ago - 1.day, last_active_at: Time.current)
    @user.sessions.create!

    assert_equal Session.count, Session.active.count + Session.expired.count
    assert_empty Session.active.where(id: Session.expired)
  end

  test "activity is recorded no more than once an hour" do
    session = @user.sessions.create!
    stale = Session::ACTIVITY_PRECISION.ago - 1.minute
    session.update_column(:last_active_at, stale)

    session.touch_activity
    assert_operator session.reload.last_active_at, :>, stale

    # A second request minutes later writes nothing, so a busy session does not
    # add a write to every page load.
    fresh = session.last_active_at
    session.touch_activity(now: fresh + 1.minute)
    assert_equal fresh.to_i, session.reload.last_active_at.to_i
  end

  test "a device label names the browser and platform it recognizes" do
    {
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" => "Safari on iPhone",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" => "Chrome on Windows",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36 Edg/120.0" => "Edge on Windows",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0" => "Firefox on Mac",
      "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36" => "Chrome on Android"
    }.each do |agent, expected|
      assert_equal expected, @user.sessions.new(user_agent: agent).device_label
    end
  end

  # An agent nobody recognizes is worth more to the user verbatim than as a
  # shrug, so it is shown rather than guessed at.
  test "an unrecognized device label falls back to the agent itself" do
    assert_equal "curl/8.4.0", @user.sessions.new(user_agent: "curl/8.4.0").device_label
    assert_equal "Unknown device", @user.sessions.new(user_agent: nil).device_label
    assert_equal "Unknown device", @user.sessions.new(user_agent: "").device_label
  end

  test "a very long device label is truncated rather than wrapping the page" do
    label = @user.sessions.new(user_agent: "x" * 500).device_label

    assert_operator label.length, :<=, 60
  end

  private

  def aged(created_at: nil, last_active_at: nil)
    session = @user.sessions.create!
    columns = { created_at: created_at, last_active_at: last_active_at }.compact
    session.update_columns(columns) if columns.any?
    session.reload
  end
end
