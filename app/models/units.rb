require "bigdecimal"
require "bigdecimal/util"

# Unit conversion for the one boundary the app has: the database stores
# kilograms, centimetres and metres, and an imperial user reads and types
# pounds, inches and miles.
#
# Storage stays canonical. Every evaluator, every coaching decision and every
# comparison in the progression engine works in metric regardless of who is
# looking — so a user switching unit systems changes nothing about their data or
# their history. Conversion happens twice and only twice: on the way into a form
# field, and on the way out of a form submission.
#
# Two rules keep that conversion honest, because a training log is a measurement
# record and a silently altered number is a corrupted one:
#
#   1. Arithmetic is BigDecimal, never Float. Float would make 45.25 lb land a
#      hair off and the error would compound through the progression engine.
#   2. Nothing is rounded to a fixed number of places for display. A value is
#      rendered at whatever precision it actually has, trailing zeros trimmed, so
#      what a user typed is what they read back. Only derived estimates — a 1RM
#      projection, a session volume — ask for a precision, and they ask
#      explicitly at the call site.
module Units
  # Exact by definition: one pound is 0.45359237 kilograms, one inch 2.54
  # centimetres, one mile 1609.344 metres.
  KG_PER_LB = BigDecimal("0.45359237")
  CM_PER_INCH = BigDecimal("2.54")
  M_PER_MILE = BigDecimal("1609.344")
  M_PER_KM = BigDecimal("1000")

  METRIC = "metric".freeze
  IMPERIAL = "imperial".freeze

  # Scale of the columns these values are written to, so a converted value is
  # never rounded finer than the database can hold. Kept in step with
  # db/migrate/20260913050000_widen_measurement_precision.rb.
  WEIGHT_SCALE = 6
  LENGTH_SCALE = 4

  # Decimals shown per quantity. Each is the coarsest scale at which a typed
  # value survives typed -> stored -> displayed -> typed unchanged, given how
  # that quantity is stored, and the round-trip tests pin every one of them:
  #
  #   weight   kg at scale 6      -> pounds are exact to 4 decimals
  #   length   cm at scale 4      -> inches are exact to 4 decimals
  #   distance whole metres       -> km and miles are exact to 3; a 4th decimal
  #                                  of miles would expose the metre rounding
  #
  # These are display ceilings, not fixed widths: trailing zeros are trimmed, so
  # a value only shows the decimals it actually has.
  WEIGHT_DECIMALS = 4
  LENGTH_DECIMALS = 4
  DISTANCE_DECIMALS = 3

  # Working precision for division, well above any display scale so the final
  # rounding is the only one that matters.
  DIVISION_DIGITS = 20

  module_function

  def imperial?(unit_system)
    unit_system.to_s == IMPERIAL
  end

  def weight_unit(unit_system) = imperial?(unit_system) ? "lb" : "kg"
  def length_unit(unit_system) = imperial?(unit_system) ? "in" : "cm"
  def distance_unit(unit_system) = imperial?(unit_system) ? "mi" : "km"
  def pace_unit(unit_system) = imperial?(unit_system) ? "/mi" : "/km"

  # Canonical kilograms -> what the user should see.
  def weight_from_kg(kg, unit_system)
    return if kg.nil?

    imperial?(unit_system) ? divide(kg, KG_PER_LB, WEIGHT_DECIMALS) : decimal(kg)
  end

  # What the user typed -> canonical kilograms.
  def weight_to_kg(value, unit_system)
    return if blank_measurement?(value)

    imperial?(unit_system) ? (decimal(value) * KG_PER_LB).round(WEIGHT_SCALE) : decimal(value)
  end

  def length_from_cm(cm, unit_system)
    return if cm.nil?

    imperial?(unit_system) ? divide(cm, CM_PER_INCH, LENGTH_DECIMALS) : decimal(cm)
  end

  def length_to_cm(value, unit_system)
    return if blank_measurement?(value)

    imperial?(unit_system) ? (decimal(value) * CM_PER_INCH).round(LENGTH_SCALE) : decimal(value)
  end

  # Distance is stored as whole metres, so the canonical value is already exact;
  # only the scale the user reads it at changes.
  def distance_from_meters(meters, unit_system)
    return if meters.nil?

    divide(meters, imperial?(unit_system) ? M_PER_MILE : M_PER_KM, DISTANCE_DECIMALS)
  end

  def distance_to_meters(value, unit_system)
    return if blank_measurement?(value)

    (decimal(value) * (imperial?(unit_system) ? M_PER_MILE : M_PER_KM)).round
  end

  # Pace arrives as seconds per kilometre and is reported per mile for an
  # imperial reader. Seconds stay whole — sub-second pace is noise.
  def pace_from_seconds_per_km(seconds, unit_system)
    return if seconds.nil?

    return seconds.round unless imperial?(unit_system)

    (decimal(seconds) * divide(M_PER_MILE, M_PER_KM, DIVISION_DIGITS)).round
  end

  # Render a converted value as a string at its own precision: no padding to a
  # fixed width, no truncation of what the user entered.
  def format_amount(value, precision: nil)
    return if value.nil?

    strip(decimal(value).round(precision || WEIGHT_DECIMALS))
  end

  def blank_measurement?(value)
    value.nil? || value.to_s.strip.empty?
  end

  def decimal(value)
    case value
    when BigDecimal then value
    when Integer then value.to_d
    when Float then value.to_d(DIVISION_DIGITS)
    when String then BigDecimal(value)
    else value.to_d
    end
  rescue ArgumentError, TypeError
    BigDecimal(value.to_f.to_s)
  end

  def divide(numerator, denominator, decimals)
    (decimal(numerator) / denominator).round(decimals)
  end

  # "225.0" -> "225", "187.53" -> "187.53". Keeps the number honest without
  # dressing it up in zeros it did not earn.
  #
  # Coerces first because BigDecimal#round returns an Integer at precision 0 —
  # which volume and other whole-unit figures ask for — and Integer#to_s does not
  # take BigDecimal's "F" argument.
  def strip(value)
    decimal(value).to_s("F").sub(/(\.\d*?)0+\z/, '\1').sub(/\.\z/, "")
  end
end
