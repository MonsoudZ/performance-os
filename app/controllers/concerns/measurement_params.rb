# Converts measurement fields from the units a form displayed back into the
# kilograms, centimetres and metres the database stores.
#
# Controllers name their own measurement fields explicitly rather than this
# guessing from a `_kg` or `_meters` suffix: a silent, name-based rule would
# quietly change the meaning of any future column that happens to match, and
# getting this wrong corrupts stored training data rather than just rendering it
# oddly.
module MeasurementParams
  extend ActiveSupport::Concern

  private

  # `nested:` names an accepts_nested_attributes key whose children carry the
  # same fields — the workout logger posts one weight per set that way.
  #
  # Metric submissions are converted too, not skipped: the conversion is the
  # identity for them, but routing every entry through the same BigDecimal path
  # means a metric user's 102.5 is parsed exactly like an imperial user's 225
  # rather than through a separate, untested branch.
  def to_canonical_units(attributes, weights: [], lengths: [], distances: [], nested: nil)
    return attributes unless Current.user

    convert_measurements(attributes, weights, lengths, distances)

    nested_children(attributes, nested).each do |child|
      convert_measurements(child, weights, lengths, distances)
    end

    attributes
  end

  # Nested attributes arrive two ways — a hash keyed by row index from a form,
  # a plain array from anything building JSON — and both mean the same thing.
  # Testing `respond_to?(:each_value)` recognised only the first, so the same
  # logical payload was converted or not depending on how it was spelled, and
  # nothing said which.
  def nested_children(attributes, nested)
    children = nested && attributes[nested]
    return [] if children.blank?

    children.respond_to?(:each_value) ? children.each_value.to_a : Array(children)
  end

  def convert_measurements(attributes, weights, lengths, distances)
    return unless attributes.respond_to?(:[])

    system = Current.user.unit_system
    convert(attributes, weights) { |value| Units.weight_to_kg(value, system) }
    convert(attributes, lengths) { |value| Units.length_to_cm(value, system) }
    convert(attributes, distances) { |value| Units.distance_to_meters(value, system) }
  end

  def convert(attributes, fields)
    fields.each do |field|
      # A blank stays blank: an unfilled weight means "not recorded", never zero.
      next if Units.blank_measurement?(attributes[field])

      attributes[field] = yield(attributes[field])
    end
  end
end
