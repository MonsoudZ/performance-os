# The day's check-in: what the user has answered, what the watch measured, and
# what the engine made of it.
#
# The four ratings are null until the user answers them, and nothing here fills
# them in. That is the whole point of the check-in — sleep quality, soreness,
# fatigue and stress are the part only the user knows, and a value carried over
# from yesterday would make "save without reading" record a day that was never
# answered. A score built from nothing is worse than no score, which is the same
# reason a day that synced only steps must not materialise a check-in.
#
# Sleep *hours* is different and does prefill: the watch measured it, so it is
# evidence rather than a guess. `sleep_from_watch` says which it was, so a
# client can show it as already known rather than as something to type.
class ReadinessCheckInSerializer
  def initialize(date:, input:, score:, decision:)
    @date = date
    @input = input
    @score = score
    @decision = decision
  end

  def as_json(*)
    {
      date: date.iso8601,
      # True only once all four subjective answers are in. Objective metrics
      # alone — a watch sync — do not count as having checked in.
      checked_in: input&.checked_in? || false,
      sleep_hours: input&.sleep_hours,
      sleep_from_watch: input&.sleep_from_watch? || false,
      ratings: DailyReadinessInput::SUBJECTIVE_FIELDS.index_with { |field| input&.public_send(field) },
      objective: {
        resting_hr: input&.resting_hr,
        hrv_sdnn_ms: input&.hrv_sdnn_ms&.to_f
      },
      source: input&.source,
      score: score && { value: score.score, components: score.components },
      decision: decision && DecisionSerializer.new(decision).as_json
    }
  end

  private

  attr_reader :date, :input, :score, :decision
end
