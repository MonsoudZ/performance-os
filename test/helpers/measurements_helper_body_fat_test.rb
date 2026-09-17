require "test_helper"

class MeasurementsHelperBodyFatTest < ActionView::TestCase
  include MeasurementsHelper

  test "a percentage renders at the precision it has" do
    assert_equal "18%", body_fat(BigDecimal("18.0"))
    assert_equal "18.25%", body_fat(BigDecimal("18.25"))
    assert_equal "7.5%", body_fat(BigDecimal("7.50"))
  end

  test "nothing recorded renders as nothing" do
    assert_nil body_fat(nil)
  end

  # The same number to everybody: a percentage is not a measurement that a unit
  # system has an opinion about.
  test "the reader's unit system does not change it" do
    Current.session = users(:two).sessions.create!(user_agent: "t", ip_address: "127.0.0.1")
    assert_equal "imperial", unit_system

    assert_equal "18.4%", body_fat(BigDecimal("18.4"))
  ensure
    Current.session = nil
  end
  # Sleep is stored in minutes and thought about in hours. Three places showed
  # it three ways, and the history page — the one whose job is reviewing what you
  # put in — printed the stored minutes, so a night entered as 7.5 hours read
  # back as "450 min".
  test "a night renders in the hours it was entered in" do
    assert_equal "7.5 h", sleep_length(7.5)
    assert_equal "8 h", sleep_length(8.0)
    assert_equal "7.45 h", sleep_length(7.45)
  end

  test "a night nobody recorded renders as nothing" do
    assert_nil sleep_length(nil)
  end
end
