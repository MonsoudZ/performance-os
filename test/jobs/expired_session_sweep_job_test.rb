require "test_helper"

class ExpiredSessionSweepJobTest < ActiveJob::TestCase
  setup { @user = users(:one) }

  test "deletes expired sessions and leaves live ones alone" do
    live = @user.sessions.create!
    idle = @user.sessions.create!
    idle.update_column(:last_active_at, Session::IDLE_TIMEOUT.ago - 1.day)
    old = @user.sessions.create!
    old.update_columns(created_at: Session::ABSOLUTE_LIFETIME.ago - 1.day, last_active_at: Time.current)

    assert_equal 2, ExpiredSessionSweepJob.new.perform

    assert Session.exists?(live.id)
    assert_not Session.exists?(idle.id)
    assert_not Session.exists?(old.id)
  end

  test "sweeping an empty table is a no-op" do
    Session.delete_all

    assert_equal 0, ExpiredSessionSweepJob.new.perform
  end
end
