# Renders canonical measurements in whatever units the signed-in user reads.
#
# Views should never print a bare `_kg`, `_cm` or `_meters` attribute, and never
# a literal unit — call `weight`, `length`, `distance` or `pace` instead.
#
# Nothing here rounds to a fixed width. A logged lift or a weigh-in is a
# measurement, and padding or truncating one misrepresents what was recorded, so
# values render at the precision they actually have with trailing zeros trimmed.
# `precision:` exists for derived estimates — a 1RM projection, a session volume
# — which are computed rather than measured, and those pass it explicitly.
module MeasurementsHelper
  def unit_system
    Current.user&.unit_system || Units::METRIC
  end

  def weight_unit = Units.weight_unit(unit_system)
  def length_unit = Units.length_unit(unit_system)
  def distance_unit = Units.distance_unit(unit_system)
  def pace_unit = Units.pace_unit(unit_system)

  # Numeric part only, converted for the user's system.
  def weight_amount(kg, precision: nil)
    return if kg.nil?

    Units.format_amount(Units.weight_from_kg(kg, unit_system), precision:)
  end

  # Numeric part plus unit, e.g. "102.5 kg" or "225 lb".
  def weight(kg, precision: nil)
    return if kg.nil?

    "#{weight_amount(kg, precision:)} #{weight_unit}"
  end

  # A percentage is the same number to everybody, so nothing is converted here.
  # It goes through the same formatter only for the trailing-zero trimming every
  # stored figure gets: a scale reporting 18.0 and one reporting 18.25 both read
  # as themselves rather than being padded to a width neither measured.
  def body_fat(pct)
    return if pct.nil?

    "#{Units.format_amount(pct)}%"
  end

  def length_amount(cm, precision: nil)
    return if cm.nil?

    Units.format_amount(Units.length_from_cm(cm, unit_system), precision: precision || Units::LENGTH_DECIMALS)
  end

  def length(cm, precision: nil)
    return if cm.nil?

    "#{length_amount(cm, precision:)} #{length_unit}"
  end

  def distance_amount(meters, precision: nil)
    return if meters.nil?

    Units.format_amount(Units.distance_from_meters(meters, unit_system), precision: precision || Units::DISTANCE_DECIMALS)
  end

  def distance(meters, precision: nil)
    return if meters.nil?

    "#{distance_amount(meters, precision:)} #{distance_unit}"
  end

  # Minutes and seconds per kilometre or per mile, e.g. "5:00 /km".
  def pace(seconds_per_km)
    return "—" if seconds_per_km.blank?

    total = Units.pace_from_seconds_per_km(seconds_per_km, unit_system)
    minutes, seconds = total.divmod(60)
    "#{minutes}:#{format('%02d', seconds)} #{pace_unit}"
  end

  # Values for measurement form fields: the stored value rendered in the units
  # the field's label claims. MeasurementParams converts it back on submit.
  def weight_field_value(kg) = weight_amount(kg)
  def length_field_value(cm) = length_amount(cm)
  def distance_field_value(meters) = distance_amount(meters)

  # Measurement inputs accept any precision the user's scale reports. Pinning a
  # step would quietly forbid real entries — a 1.25 kg micro-plate, a 2.5 lb
  # change on the scale — and browsers reject off-step values outright.
  def measurement_step = "any"

  # A composed daily-plan lift directive's headline, rebuilt in the reader's
  # units. Same bargain as progression_headline: the stored sentence is the
  # record, this is the presentation. Directives written before the rule carried
  # next_weight_kg fall through to the stored text.
  def lift_headline(lift)
    following = lift["next_weight_kg"]
    return lift["headline"] unless following

    case lift["action"]
    when "increase" then weight(following)
    when "conditional_increase" then "#{weight(following)} if warm-ups are crisp"
    when "deload" then "Deload to #{weight(following)}"
    else lift["headline"]
    end
  end

  # A progression decision's headline, rebuilt in the reader's units.
  #
  # The stored headline is part of an immutable audit record and stays in
  # kilograms deliberately. Where the decision also carries the numbers behind
  # that sentence, the UI composes its own copy rather than doing string surgery
  # on the record — and falls back to the stored text when it cannot.
  def progression_headline(output)
    current = output["current_weight_kg"]
    following = output["next_weight_kg"]

    case output["status"]
    when "increase"
      return output["headline"] unless current && following

      "Add #{weight(Units.decimal(following) - Units.decimal(current))} next time"
    when "deload"
      return output["headline"] unless following

      "Deload to #{weight(following)}"
    else
      output["headline"]
    end
  end
end
