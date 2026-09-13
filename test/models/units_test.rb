require "test_helper"

class UnitsTest < ActiveSupport::TestCase
  test "metric conversions are the identity" do
    assert_equal 102.5, Units.weight_from_kg(102.5, "metric")
    assert_equal 102.5, Units.weight_to_kg("102.5", "metric")
    assert_equal 180.0, Units.length_from_cm(180, "metric")
    assert_equal 180.0, Units.length_to_cm("180", "metric")
  end

  test "converts kilograms to pounds and back" do
    assert_in_delta 220.462, Units.weight_from_kg(100, "imperial"), 0.001
    assert_in_delta 45.359, Units.weight_to_kg(100, "imperial"), 0.001
  end

  test "a weight survives the form round trip" do
    typed = 225.0
    stored = Units.weight_to_kg(typed, "imperial")

    # The column is decimal(6,2), so the round trip goes through that precision.
    assert_in_delta typed, Units.weight_from_kg(stored.round(2), "imperial"), 0.05
  end

  test "converts centimetres to inches and back" do
    assert_in_delta 70.866, Units.length_from_cm(180, "imperial"), 0.001
    assert_in_delta 177.8, Units.length_to_cm(70, "imperial"), 0.001
  end

  test "treats nil and blank as absent rather than zero" do
    assert_nil Units.weight_to_kg(nil, "imperial")
    assert_nil Units.weight_to_kg("", "imperial")
    assert_nil Units.weight_to_kg("   ", "imperial")
    assert_nil Units.weight_from_kg(nil, "imperial")
    assert_nil Units.length_to_cm("", "imperial")
    assert_nil Units.length_from_cm(nil, "imperial")
  end

  test "zero is a real value, not an absent one" do
    assert_equal 0.0, Units.weight_to_kg("0", "imperial")
    assert_equal 0.0, Units.weight_from_kg(0, "imperial")
  end

  test "reports the right unit label and step per system" do
    assert_equal "kg", Units.weight_unit("metric")
    assert_equal "lb", Units.weight_unit("imperial")
    assert_equal "cm", Units.length_unit("metric")
    assert_equal "in", Units.length_unit("imperial")
    assert_equal 0.25, Units.weight_step("metric")
    assert_equal 1.0, Units.weight_step("imperial")
  end

  test "falls back to metric precision for an unrecognized system" do
    assert_equal Units.weight_precision("metric"), Units.weight_precision("klingon")
    assert_not Units.imperial?("klingon")
    assert_not Units.imperial?(nil)
  end
end
