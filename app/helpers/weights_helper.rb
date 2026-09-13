# Renders canonical kilograms in whatever units the signed-in user reads.
#
# Views should never print a bare `_kg` attribute or a literal "kg" again — call
# `weight` for a value with its unit, or `weight_amount` when the unit is already
# in a nearby label.
module WeightsHelper
  def weight_unit
    Current.user&.weight_unit || "kg"
  end

  def length_unit
    Current.user&.length_unit || "cm"
  end

  def unit_system
    Current.user&.unit_system || Units::METRIC
  end

  # Numeric part only, converted and rounded for the user's system.
  def weight_amount(kg, precision: nil)
    return unless kg

    number_with_precision(
      Units.weight_from_kg(kg, unit_system),
      precision: precision || Units.weight_precision(unit_system),
      strip_insignificant_zeros: true
    )
  end

  # Numeric part plus unit, e.g. "102.5 kg" or "226 lb".
  def weight(kg, precision: nil)
    return unless kg

    "#{weight_amount(kg, precision:)} #{weight_unit}"
  end

  def length_amount(cm, precision: nil)
    return unless cm

    number_with_precision(
      Units.length_from_cm(cm, unit_system),
      precision: precision || Units.length_precision(unit_system),
      strip_insignificant_zeros: true
    )
  end

  # Value for a weight form field: the stored kilograms rendered in the units the
  # field's label claims. WeightParams converts it back on submit.
  def weight_field_value(kg, precision: nil)
    return if kg.nil?

    Units.weight_from_kg(kg, unit_system).round(precision || Units.weight_precision(unit_system))
  end

  def length_field_value(cm, precision: nil)
    return if cm.nil?

    Units.length_from_cm(cm, unit_system).round(precision || Units.length_precision(unit_system))
  end

  def weight_field_step
    Units.weight_step(unit_system)
  end

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

      "Add #{weight(following - current)} next time"
    when "deload"
      return output["headline"] unless following

      "Deload to #{weight(following)}"
    else
      output["headline"]
    end
  end
end
