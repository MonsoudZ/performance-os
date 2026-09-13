# Unit conversion for the one boundary the app has: the database stores
# kilograms and centimetres, and an imperial user reads and types pounds and
# inches.
#
# Storage stays canonical. Every evaluator, every coaching decision, and every
# comparison in the progression engine works in kilograms regardless of who is
# looking — so a user switching unit systems changes nothing about their data or
# their history. Conversion happens twice and only twice: on the way into a form
# field, and on the way out of a form submission.
module Units
  KG_PER_LB = 0.45359237
  CM_PER_INCH = 2.54

  METRIC = "metric".freeze
  IMPERIAL = "imperial".freeze

  # Pounds are a finer unit than kilograms, but nobody logs a lift to a
  # hundredth of a pound. One decimal keeps a 2.5 kg increment legible (5.5 lb)
  # without implying precision the scale never had.
  WEIGHT_PRECISION = { METRIC => 2, IMPERIAL => 1 }.freeze
  LENGTH_PRECISION = { METRIC => 1, IMPERIAL => 1 }.freeze

  module_function

  def imperial?(unit_system)
    unit_system.to_s == IMPERIAL
  end

  def weight_unit(unit_system)
    imperial?(unit_system) ? "lb" : "kg"
  end

  def length_unit(unit_system)
    imperial?(unit_system) ? "in" : "cm"
  end

  # Canonical kilograms -> what the user should see.
  def weight_from_kg(kg, unit_system)
    return if kg.nil?

    imperial?(unit_system) ? kg.to_f / KG_PER_LB : kg.to_f
  end

  # What the user typed -> canonical kilograms.
  def weight_to_kg(value, unit_system)
    return if value.nil? || value.to_s.strip.empty?

    imperial?(unit_system) ? value.to_f * KG_PER_LB : value.to_f
  end

  def length_from_cm(cm, unit_system)
    return if cm.nil?

    imperial?(unit_system) ? cm.to_f / CM_PER_INCH : cm.to_f
  end

  def length_to_cm(value, unit_system)
    return if value.nil? || value.to_s.strip.empty?

    imperial?(unit_system) ? value.to_f * CM_PER_INCH : value.to_f
  end

  def weight_precision(unit_system)
    WEIGHT_PRECISION.fetch(unit_system.to_s, WEIGHT_PRECISION.fetch(METRIC))
  end

  def length_precision(unit_system)
    LENGTH_PRECISION.fetch(unit_system.to_s, LENGTH_PRECISION.fetch(METRIC))
  end

  # Smallest load step the user can meaningfully enter. Plates come in 2.5 kg
  # and 5 lb pairs, so the step follows the unit rather than converting.
  def weight_step(unit_system)
    imperial?(unit_system) ? 1.0 : 0.25
  end
end
