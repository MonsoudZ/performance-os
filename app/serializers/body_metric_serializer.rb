# One weigh-in.
#
# `weight_kg` is the stored figure, unconverted, like every measurement crossing
# this boundary: the client renders it through the `unit_system` on the profile.
# It is exact rather than rounded to a display width — the column carries six
# decimal places precisely so a re-save cannot silently change what the user
# entered, and rounding here would hand that back.
#
# `source` says whether a person stood on a scale and typed this or a watch
# derived it. The two are separate rows for the same day on purpose: a sync that
# adds readings re-derives its own row and never touches a manual one.
class BodyMetricSerializer
  def initialize(body_metric)
    @body_metric = body_metric
  end

  def as_json(*)
    {
      id: body_metric.id,
      measured_on: body_metric.measured_on.iso8601,
      weight_kg: body_metric.weight_kg&.to_f,
      body_fat_pct: body_metric.body_fat_pct&.to_f,
      source: body_metric.source,
      # Whether a watch derived this rather than a person typing it. A derived
      # row re-derives itself on the next sync, so removing one only makes it
      # come back — worth a client saying, which it cannot do without being told.
      derived: body_metric.source != "manual"
    }
  end

  private

  attr_reader :body_metric
end
