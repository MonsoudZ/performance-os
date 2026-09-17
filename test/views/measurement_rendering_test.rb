require "test_helper"

# One property over every view, like ResponsiveLayoutTest and ElementIdsTest:
# a template never prints a stored measurement itself.
#
# The database stores kilograms, centimetres and metres for everybody, so a
# template that reaches for one of those columns and interpolates it shows an
# imperial reader a metric number — which reads as plausible and wrong, the worst
# kind of display bug. Conversion belongs to `MeasurementsHelper`, and this is
# what keeps it there.
class MeasurementRenderingTest < ActiveSupport::TestCase
  VIEWS = Dir[Rails.root.join("app/views/**/*.erb")].freeze

  # Columns holding a value in the unit the database stores rather than the one
  # the reader uses.
  CANONICAL_ATTRIBUTES = /\.(weight_kg|height_cm|ewma_kg|raw_kg|trend_weight_kg|current_weight_kg|next_weight_kg|increment_kg|distance_meters|total_distance_meters)\b/

  # Everything in MeasurementsHelper that converts on the way out. A template
  # naming a canonical column inside one of these is doing the right thing.
  # Called with or without parentheses — both spellings appear in these views.
  CONVERTERS = /\b(weight|weight_amount|weight_number|weight_field_value|length|length_amount|length_field_value|distance|distance_amount|distance_field_value|pace|decision_field_value)[ (]/

  # A column named to ask a question about rather than to show.
  PREDICATES = /#{CANONICAL_ATTRIBUTES.source}\.(present\?|blank\?|nil\?|zero\?|positive\?|any\?)/

  test "no template prints a stored measurement without converting it" do
    offenders = VIEWS.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        # Only what is printed. Asking whether a weight exists is not rendering
        # one, and a control tag renders nothing at all.
        next unless line.include?("<%=")
        next unless line.match?(CANONICAL_ATTRIBUTES)
        next if line.match?(PREDICATES)
        next if line.match?(CONVERTERS)

        "#{path.delete_prefix(Rails.root.to_s + '/')}:#{index + 1}: #{line.strip}"
      end
    end

    assert_empty offenders,
      "these print a stored measurement directly; route them through MeasurementsHelper"
  end

  # `Units` is the conversion layer. A view calling it is one edit away from
  # calling it without a unit system, which converts nothing and looks fine.
  test "no template reaches into Units itself" do
    offenders = VIEWS.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.match?(/\bUnits\./)

        "#{path.delete_prefix(Rails.root.to_s + '/')}:#{index + 1}: #{line.strip}"
      end
    end

    assert_empty offenders, "use a MeasurementsHelper method instead of Units directly"
  end
end
