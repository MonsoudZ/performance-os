require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "computes calendar dates in the user's time zone" do
    user = users(:one)
    user.update!(time_zone: "America/Denver")
    instant = Time.utc(2026, 6, 10, 5, 30)

    assert_equal Date.new(2026, 6, 9), user.local_date_at(instant)
    assert user.local_day_range(Date.new(2026, 6, 9)).cover?(instant)
  end

  test "rejects unknown time zones" do
    user = users(:one)

    assert_not user.update(time_zone: "Mars/Olympus")
    assert_includes user.errors[:time_zone], "is not recognized"
  end
end
