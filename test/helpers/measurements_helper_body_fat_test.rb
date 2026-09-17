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
end
