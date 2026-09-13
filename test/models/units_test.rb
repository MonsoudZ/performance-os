require "test_helper"

class UnitsTest < ActiveSupport::TestCase
  test "metric conversions are the identity" do
    assert_equal Units.decimal("102.5"), Units.weight_from_kg(BigDecimal("102.5"), "metric")
    assert_equal Units.decimal("102.5"), Units.weight_to_kg("102.5", "metric")
    assert_equal Units.decimal(180), Units.length_from_cm(180, "metric")
    assert_equal Units.decimal(180), Units.length_to_cm("180", "metric")
  end

  test "converts kilograms to pounds and back" do
    assert_in_delta 220.462, Units.weight_from_kg(100, "imperial"), 0.001
    assert_in_delta 45.359, Units.weight_to_kg(100, "imperial"), 0.001
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

  test "reports the right unit label per system" do
    assert_equal "kg", Units.weight_unit("metric")
    assert_equal "lb", Units.weight_unit("imperial")
    assert_equal "cm", Units.length_unit("metric")
    assert_equal "in", Units.length_unit("imperial")
    assert_equal "km", Units.distance_unit("metric")
    assert_equal "mi", Units.distance_unit("imperial")
    assert_equal "/km", Units.pace_unit("metric")
    assert_equal "/mi", Units.pace_unit("imperial")
  end

  test "treats an unrecognized system as metric" do
    assert_not Units.imperial?("klingon")
    assert_not Units.imperial?(nil)
  end

  # The point of the whole module: a number a user typed must come back out of
  # the database identical, or a training log is not a record of anything.
  test "every pound a user could type survives the round trip exactly" do
    [ 225, 45.25, 187.53, 312.75, 2.5, 140.2, 33.125, 1.0625, 0.5 ].each do |typed|
      stored = Units.weight_to_kg(typed, "imperial")
      read_back = Units.format_amount(Units.weight_from_kg(stored, "imperial"))

      assert_equal Units.format_amount(typed), read_back,
        "#{typed} lb stored as #{stored.to_s('F')} kg came back as #{read_back}"
    end
  end

  test "every inch a user could type survives the round trip exactly" do
    [ 70, 70.5, 70.53, 68.25, 72.125 ].each do |typed|
      stored = Units.length_to_cm(typed, "imperial")
      read_back = Units.format_amount(Units.length_from_cm(stored, "imperial"), precision: Units::LENGTH_DECIMALS)

      assert_equal Units.format_amount(typed), read_back
    end
  end

  test "distances survive the round trip through whole metres" do
    { "metric" => [ 5, 5.255, 42.195, 10.5 ], "imperial" => [ 3.1, 26.22, 13.11, 5 ] }.each do |system, values|
      values.each do |typed|
        stored = Units.distance_to_meters(typed, system)
        read_back = Units.format_amount(Units.distance_from_meters(stored, system), precision: Units::DISTANCE_DECIMALS)

        assert_equal Units.format_amount(typed), read_back,
          "#{typed} #{Units.distance_unit(system)} stored as #{stored} m came back as #{read_back}"
      end
    end
  end

  test "re-saving an unchanged value does not move it" do
    stored = Units.weight_to_kg(45.25, "imperial")

    5.times do
      shown = Units.format_amount(Units.weight_from_kg(stored, "imperial"))
      resaved = Units.weight_to_kg(shown, "imperial")

      assert_equal stored, resaved, "opening and re-saving a set must not drift its weight"
      stored = resaved
    end
  end

  test "the display scale never out-resolves the column it came from" do
    assert_operator Units::WEIGHT_SCALE, :>, Units::WEIGHT_DECIMALS,
      "kilograms must be stored finer than pounds are shown, or the rounding leaks back"
    assert_operator Units::LENGTH_SCALE, :>=, Units::LENGTH_DECIMALS
  end

  test "arithmetic is exact, not floating point" do
    assert_instance_of BigDecimal, Units.weight_to_kg("0.1", "imperial")
    assert_instance_of BigDecimal, Units.weight_from_kg(BigDecimal("0.1"), "imperial")

    # 0.1 + 0.2 != 0.3 in binary floating point; it must here.
    sum = Units.decimal("0.1") + Units.decimal("0.2")

    assert_equal Units.decimal("0.3"), sum
  end

  test "renders a value at its own precision without padding or truncating" do
    assert_equal "225", Units.format_amount(BigDecimal("225.0000"))
    assert_equal "187.53", Units.format_amount(BigDecimal("187.5300"))
    assert_equal "0.5", Units.format_amount(BigDecimal("0.50"))
    assert_equal "100", Units.format_amount(100)
    assert_nil Units.format_amount(nil)
  end

  test "converts pace per kilometre into pace per mile" do
    assert_equal 300, Units.pace_from_seconds_per_km(300, "metric")
    assert_equal 483, Units.pace_from_seconds_per_km(300, "imperial")
    assert_nil Units.pace_from_seconds_per_km(nil, "imperial")
  end
end
