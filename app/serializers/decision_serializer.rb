# A coaching decision, whole.
#
# `output` ships as it was written rather than being picked apart field by
# field, for the same reason `coaching_decisions/_snapshot` renders it
# generically: the shape belongs to the rule, so a new rule needs no work here.
# A client that knows `daily_nutrition` reads `output["totals"]`; one that does
# not can still show the headline and the guidance, which every rule writes.
#
# It is a record, so it crosses the boundary as it was stored — the same rule
# the account export follows. Nothing in a `daily_nutrition` or `daily_readiness`
# output is unit-system dependent (kilocalories and grams read the same to
# everybody), and from `double_progression` rule_version 4.0.0 the prose names no
# unit at all: the weights live in `current_weight_kg`/`next_weight_kg`, in
# kilograms like every other measurement here, and the client converts at its own
# display edge.
#
# `id` is the whole audit trail in one number: /coaching_decisions/:id renders
# the inputs the rule saw alongside what it concluded.
class DecisionSerializer
  def initialize(decision)
    @decision = decision
  end

  def as_json(*)
    {
      id: decision.id,
      decision_type: decision.decision_type,
      rule_key: decision.rule_key,
      rule_version: decision.rule_version,
      confidence: decision.confidence,
      created_at: decision.created_at.iso8601,
      # "Withdrawn" is what the user is told; "retracted" is what the code says.
      withdrawn: decision.retracted_at.present?,
      withdrawn_because: decision.retraction_explanation,
      output: decision.output
    }
  end

  private

  attr_reader :decision
end
