require "test_helper"

# The decision table is the product's central claim, and its rules are the ones
# most easily broken by accident: a lookup that forgets `active_evidence` quietly
# feeds a retracted recommendation into a new decision, and the JSONB scopes are
# string comparisons against untyped data.
class CoachingDecisionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @exercise = Exercise.create!(name: "Zzz Decision Squat", modality: "barbell")
  end

  test "requires the fields that make a decision interpretable later" do
    decision = CoachingDecision.new(user: @user, inputs: {}, output: {})

    assert_not decision.valid?
    assert_includes decision.errors.attribute_names, :decision_type
    assert_includes decision.errors.attribute_names, :rule_key
    assert_includes decision.errors.attribute_names, :rule_version
  end

  test "confidence is limited to the three levels the UI knows how to render" do
    assert build(confidence: "high").valid?
    assert_not build(confidence: "very-high").valid?
    assert_not build(confidence: nil).valid?
  end

  test "retracting records a reason and a time" do
    decision = create

    assert_nil decision.retracted_at
    assert_not decision.retracted_at?

    decision.retract!(reason: "workout_deleted")

    assert_predicate decision.reload, :retracted_at?
    assert_equal "workout_deleted", decision.retraction_reason
  end

  test "retracting twice keeps the first reason and time" do
    decision = create
    decision.retract!(reason: "workout_deleted")
    first_time = decision.retracted_at

    travel 1.hour do
      decision.retract!(reason: "something_else")
    end

    assert_equal "workout_deleted", decision.reload.retraction_reason
    assert_equal first_time.to_i, decision.retracted_at.to_i,
      "a decision is retracted once; a second call must not rewrite the record"
  end

  test "a retraction cannot be recorded without a reason" do
    decision = create
    decision.retracted_at = Time.current

    assert_not decision.valid?
    assert_includes decision.errors.attribute_names, :retraction_reason
  end

  test "withdrawn is the complement of active_evidence" do
    kept = create
    retracted = create
    retracted.retract!(reason: "workout_session_deleted")

    assert_equal [ retracted ], @user.coaching_decisions.withdrawn.to_a
    assert_equal [ kept ], @user.coaching_decisions.active_evidence.to_a
  end

  test "a retraction reason reads as a sentence a user can follow" do
    decision = create
    decision.retract!(reason: "workout_session_corrected")

    assert_equal "the workout behind it was corrected", decision.retraction_explanation
  end

  test "an unrecognized retraction reason still renders readably" do
    decision = create
    decision.retract!(reason: "some_future_reason")

    assert_equal "some future reason", decision.retraction_explanation
  end

  test "a decision that was never retracted has no explanation" do
    assert_nil create.retraction_explanation
  end

  test "active_evidence excludes retracted decisions" do
    kept = create
    retracted = create
    retracted.retract!(reason: "superseded")

    active = @user.coaching_decisions.active_evidence

    assert_includes active, kept
    assert_not_includes active, retracted
  end

  test "for_input matches a top-level JSON key regardless of value type" do
    dated = create(inputs: { "metric_date" => Date.new(2026, 3, 1).iso8601 })
    numbered = create(inputs: { "exercise_id" => @exercise.id })
    create(inputs: { "metric_date" => Date.new(2026, 3, 2).iso8601 })

    assert_equal [ dated ], @user.coaching_decisions.for_input("metric_date", "2026-03-01").to_a
    assert_equal [ numbered ], @user.coaching_decisions.for_input("exercise_id", @exercise.id).to_a,
      "an integer id is compared as text, the way it is stored"
  end

  test "for_input does not match a key nested deeper" do
    create(inputs: { "prescription" => { "id" => 42 } })

    assert_empty @user.coaching_decisions.for_input("id", 42)
  end

  test "for_prescription reaches the id nested in the prescription snapshot" do
    matching = create(inputs: { "prescription" => { "id" => 7, "rep_min" => 6 } })
    create(inputs: { "prescription" => { "id" => 8 } })

    assert_equal [ matching ], @user.coaching_decisions.for_prescription(7).to_a
  end

  test "latest_first orders newest to oldest" do
    older = create(created_at: 2.days.ago)
    newer = create(created_at: 1.day.ago)

    assert_equal [ newer, older ], @user.coaching_decisions.latest_first.to_a
  end

  test "of_type narrows to one decision type" do
    readiness = create(decision_type: "daily_readiness")
    create(decision_type: "daily_nutrition")

    assert_equal [ readiness ], @user.coaching_decisions.of_type("daily_readiness").to_a
  end

  test "a parent links to its children with a role" do
    parent = create(decision_type: "daily_training")
    child = create(decision_type: "daily_readiness")
    parent.child_links.create!(child_decision: child, role: "readiness")

    assert_equal [ child ], parent.reload.child_decisions.to_a
    assert_equal [ parent ], child.reload.parent_decisions.to_a
  end

  test "the same child cannot be linked to one parent twice" do
    parent = create
    child = create
    parent.child_links.create!(child_decision: child, role: "readiness")
    duplicate = parent.child_links.build(child_decision: child, role: "progression")

    assert_not duplicate.valid?
  end

  test "a decision cannot be its own child" do
    decision = create
    link = decision.child_links.build(child_decision: decision, role: "readiness")

    assert_not link.valid?
    assert_includes link.errors.attribute_names, :child_decision
  end

  test "a link cannot cross users" do
    mine = create
    theirs = create(user: users(:two))
    link = mine.child_links.build(child_decision: theirs, role: "readiness")

    assert_not link.valid?
    assert_includes link.errors.attribute_names, :child_decision
  end

  test "roles are limited to the four the schema allows" do
    parent = create
    child = create

    assert parent.child_links.build(child_decision: child, role: "nutrition").valid?
    assert_not parent.child_links.build(child_decision: child, role: "vibes").valid?
  end

  test "a decision that something else cites cannot be deleted out from under it" do
    parent = create
    child = create
    parent.child_links.create!(child_decision: child, role: "readiness")

    assert_raises(ActiveRecord::DeleteRestrictionError) { child.destroy }
  end

  test "deleting a parent takes its links but not its children" do
    parent = create
    child = create
    parent.child_links.create!(child_decision: child, role: "readiness")

    assert_difference -> { CoachingDecisionLink.count }, -1 do
      parent.destroy
    end

    assert child.reload.persisted?, "the evidence outlives the decision that cited it"
  end

  private

  def build(**attributes)
    @user.coaching_decisions.build({
      decision_type: "daily_readiness",
      rule_key: "daily_readiness.v1",
      rule_version: "1.0.0",
      inputs: {},
      output: {},
      citations: [],
      confidence: "high"
    }.merge(attributes))
  end

  def create(**attributes)
    user = attributes.delete(:user) || @user
    record = build(**attributes)
    record.user = user
    record.save!
    record
  end
  # The database refuses this too, and both matter: the constraint is what makes
  # it true of every writer, the validation is what turns it into a sentence
  # rather than a 500. A type one letter wrong is a decision every `of_type`
  # lookup misses — it exists, counts towards nothing and answers no question.
  test "a decision type the engine does not write is refused" do
    decision = users(:one).coaching_decisions.new(
      decision_type: "daily_readines", rule_key: "x", rule_version: "1.0.0",
      confidence: "low", inputs: {}, output: {}, citations: []
    )

    assert_not decision.valid?
    assert_includes decision.errors[:decision_type], "is not included in the list"
  end

  test "every type the engine writes is one the model accepts" do
    CoachingDecision::DECISION_TYPES.each do |decision_type|
      decision = users(:one).coaching_decisions.new(
        decision_type: decision_type, rule_key: "x", rule_version: "1.0.0",
        confidence: "low", inputs: {}, output: {}, citations: []
      )

      assert decision.valid?, "#{decision_type}: #{decision.errors.full_messages.to_sentence}"
    end
  end
  # A type with no label falls back to `humanize`, which reads acceptably and
  # hides the omission — the labels had five of the six, and the missing one was
  # the same one missing from the table in CLAUDE.md.
  test "every decision type the engine writes has a label written for it" do
    missing = CoachingDecision::DECISION_TYPES -
      CoachingDecisionsHelper::DECISION_TYPE_LABELS.keys

    assert_empty missing, "these fall back to humanize instead of a written label"
  end

  test "no label names a type the engine does not write" do
    extra = CoachingDecisionsHelper::DECISION_TYPE_LABELS.keys -
      CoachingDecision::DECISION_TYPES

    assert_empty extra
  end
end
