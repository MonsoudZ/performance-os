# Converts weight and length fields from the units a form displayed back into
# the kilograms and centimetres the database stores.
#
# Controllers name their own measurement fields explicitly rather than this
# guessing from the `_kg` suffix: a silent, name-based rule would quietly change
# the meaning of any future column that happens to match, and getting this wrong
# corrupts stored training data rather than just rendering it oddly.
module WeightParams
  extend ActiveSupport::Concern

  private

  # `nested:` names an accepts_nested_attributes key whose children carry the
  # same fields — the workout logger posts one weight per set that way.
  def to_canonical_units(attributes, weights: [], lengths: [], nested: nil)
    return attributes unless Current.user&.imperial?

    convert_measurements(attributes, weights, lengths)

    if nested && attributes[nested].respond_to?(:each_value)
      attributes[nested].each_value { |child| convert_measurements(child, weights, lengths) }
    end

    attributes
  end

  def convert_measurements(attributes, weights, lengths)
    return unless attributes.respond_to?(:[])

    weights.each do |field|
      next if attributes[field].blank?

      attributes[field] = Units.weight_to_kg(attributes[field], Current.user.unit_system)
    end

    lengths.each do |field|
      next if attributes[field].blank?

      attributes[field] = Units.length_to_cm(attributes[field], Current.user.unit_system)
    end
  end
end
