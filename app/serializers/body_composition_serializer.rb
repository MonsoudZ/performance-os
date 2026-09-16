# What the body-composition half of the nutrition page knows: what was weighed,
# what the trend makes of it, and what the engine concluded about expenditure.
#
# The trend is the thing worth showing rather than the raw weigh-ins. A single
# morning reading moves with water and yesterday's salt; `WeightTrendMaterializer`
# smooths it, and every rule downstream — the calorie target, the protein target,
# the expenditure estimate — reads the smoothed figure, never the raw one. Both
# ship, because a client that draws only the trend cannot show the user the
# reading it is asking them to trust.
#
# Weights are in kilograms throughout, unconverted.
class BodyCompositionSerializer
  def initialize(metrics:, trends:, expenditure:)
    @metrics = metrics
    @trends = trends
    @expenditure = expenditure
  end

  def as_json(*)
    {
      metrics: metrics.map { |metric| BodyMetricSerializer.new(metric).as_json },
      trend: trends.map { |trend| trend_json(trend) },
      expenditure: expenditure && expenditure_json
    }
  end

  private

  attr_reader :metrics, :trends, :expenditure

  def trend_json(trend)
    {
      trend_date: trend.trend_date.iso8601,
      # What the scale said that day, averaged if it was stood on twice.
      raw_kg: trend.raw_kg&.to_f,
      # The smoothed figure, and the one every rule downstream actually reads.
      ewma_kg: trend.ewma_kg.to_f
    }
  end

  # Null until there is enough evidence to estimate one, which is the honest
  # answer rather than a default: `basis` says which kind of evidence it rests
  # on and `confidence` how much of it there was.
  def expenditure_json
    {
      estimate_date: expenditure.estimate_date.iso8601,
      estimated_tdee: expenditure.estimated_tdee.to_f,
      basis: expenditure.basis,
      confidence: expenditure.confidence,
      intake_kcal: expenditure.intake_kcal&.to_f,
      trend_weight_kg: expenditure.trend_weight_kg&.to_f
    }
  end
end
