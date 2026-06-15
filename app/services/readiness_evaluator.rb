class ReadinessEvaluator
  RULE_KEY = "daily_readiness.v1"
  RULE_VERSION = "1.0.0"

  METRICS = {
    sleep_quality: { weight: 0.20 },
    sleep_minutes: { weight: 0.15 },
    soreness: { weight: 0.15 },
    fatigue: { weight: 0.15 },
    stress: { weight: 0.10 },
    hrv_sdnn_ms: { weight: 0.15 },
    resting_hr: { weight: 0.10 }
  }.freeze
  OBJECTIVE_METRICS = %i[hrv_sdnn_ms resting_hr].freeze
  BASELINE_DAYS = 7

  def initialize(readiness_input)
    @readiness_input = readiness_input
  end

  def call
    components = scored_components
    score = weighted_score(components)
    recommendation = recommendation_for(score)
    return [ current_score, current_decision ] if current_decision_matches?

    ApplicationRecord.transaction do
      readiness_input.user.readiness_scores.where(score_date: readiness_input.metric_date).delete_all
      readiness_score = readiness_input.user.readiness_scores.create!(
        score_date: readiness_input.metric_date,
        score: score,
        components: components
      )

      decision = CoachingDecision.create!(
        user: readiness_input.user,
        decision_type: "daily_readiness",
        rule_key: RULE_KEY,
        rule_version: RULE_VERSION,
        inputs: serialized_inputs,
        output: recommendation.merge("readiness_score" => score),
        citations: [],
        confidence: confidence_for(components)
      )

      [ readiness_score, decision ]
    end
  end

  private

  attr_reader :readiness_input

  def scored_components
    METRICS.each_with_object({}) do |(metric, config), components|
      value = readiness_input.public_send(metric)
      next if value.nil?
      next if OBJECTIVE_METRICS.include?(metric) && baseline_for(metric).nil?

      normalized = normalize(metric, value)
      components[metric] = {
        "value" => value.to_f,
        "normalized" => normalized.round(3),
        "weight" => config[:weight]
      }
    end
  end

  def weighted_score(components)
    return 50 if components.empty?

    available_weight = components.sum { |_metric, details| details["weight"] }
    weighted_total = components.sum do |_metric, details|
      details["normalized"] * details["weight"]
    end

    (weighted_total / available_weight * 100).round.clamp(0, 100)
  end

  def normalize(metric, value)
    case metric
    when :sleep_minutes
      ((value.to_f - 300) / 180).clamp(0, 1)
    when :sleep_quality
      (value.to_f - 1) / 4
    when :hrv_sdnn_ms
      relative_score(value, baseline_for(metric))
    when :resting_hr
      1 - relative_score(value, baseline_for(metric))
    else
      1 - ((value.to_f - 1) / 4)
    end
  end

  def relative_score(value, baseline)
    delta = (value.to_f - baseline) / baseline
    (0.5 + (delta / 0.4)).clamp(0, 1)
  end

  def baseline_for(metric)
    @baselines ||= {}
    return @baselines[metric] if @baselines.key?(metric)

    values = readiness_input.user.daily_readiness_inputs
      .where("metric_date < ?", readiness_input.metric_date)
      .where.not(metric => nil)
      .order(metric_date: :desc)
      .limit(28)
      .pluck(metric)
      .map(&:to_f)
      .sort
    @baselines[metric] = values.size >= BASELINE_DAYS ? median(values) : nil
  end

  def median(values)
    midpoint = values.length / 2
    values.length.odd? ? values[midpoint] : (values[midpoint - 1] + values[midpoint]) / 2
  end

  def baseline_snapshot
    OBJECTIVE_METRICS.index_with { |metric| baseline_for(metric) }
  end

  def input_snapshot
    readiness_input.attributes.slice(*METRICS.keys.map(&:to_s), "source").merge(
      "readiness_input_id" => readiness_input.id,
      "metric_date" => readiness_input.metric_date,
      "objective_baselines" => baseline_snapshot
    )
  end

  def serialized_inputs
    @serialized_inputs ||= JSON.parse(input_snapshot.to_json)
  end

  def current_decision
    @current_decision ||= readiness_input.user.coaching_decisions
      .of_type("daily_readiness")
      .where(rule_key: RULE_KEY)
      .for_input("metric_date", readiness_input.metric_date.iso8601)
      .latest_first
      .first
  end

  def current_decision_matches?
    current_decision&.inputs == serialized_inputs
  end

  def current_score
    readiness_input.user.readiness_scores.find_by(score_date: readiness_input.metric_date)
  end

  def recommendation_for(score)
    case score
    when 75..100
      {
        "status" => "push",
        "headline" => "Green light",
        "guidance" => "Train as planned. If warm-ups move well, pursue the top end of your target range."
      }
    when 50..74
      {
        "status" => "steady",
        "headline" => "Proceed, but stay honest",
        "guidance" => "Keep the session, cap effort around RPE 8, and avoid adding unplanned volume."
      }
    else
      {
        "status" => "recover",
        "headline" => "Recovery has the floor",
        "guidance" => "Reduce working volume by 30–40% or choose low-intensity movement today."
      }
    end
  end

  def confidence_for(components)
    return "low" if OBJECTIVE_METRICS.any? { |metric| readiness_input.public_send(metric).present? && baseline_for(metric).nil? }

    case components.size
    when 5..7 then "high"
    when 2..4 then "moderate"
    else "low"
    end
  end
end
