# Renders a stored decision snapshot so a person can read it.
#
# `inputs` and `output` are untyped JSONB written by whichever rule produced the
# decision, so nothing here may assume a shape. The goal is that a user can open
# any decision and understand what the engine saw and what it concluded, without
# the page pretending the data is something it is not.
module CoachingDecisionsHelper
  DECISION_TYPE_LABELS = {
    "daily_readiness" => "Daily readiness",
    "double_progression" => "Lift progression",
    "daily_nutrition" => "Daily nutrition",
    "nutrition_adjustment" => "Calorie adjustment",
    "weekly_review" => "Weekly review",
    "daily_training" => "Daily training plan"
  }.freeze

  # Suffixes that identify a measurement, so the value renders in the reader's
  # units and the label does not repeat the canonical one.
  MEASUREMENT_SUFFIXES = %w[_kg _cm _meters _g _ms _bpm _kcal _minutes _seconds].freeze

  # A `source` says where the rule got a number from, and the stored values are
  # rule names. Read back to a user they have to be sentences — the same reason
  # CoachingDecision::RETRACTION_EXPLANATIONS exists. Scoped to that one key so
  # an unrelated field that happens to hold one of these words is left alone.
  SOURCE_LABELS = {
    "block_scheme" => "the training block’s scheme",
    "prescription" => "the target’s own numbers",
    "healthkit" => "synced from a device",
    "mixed" => "a check-in plus synced data",
    "manual" => "entered by hand"
  }.freeze

  def decision_type_label(decision_type)
    DECISION_TYPE_LABELS.fetch(decision_type) { decision_type.to_s.humanize }
  end

  # "next_weight_kg" -> "Next weight". The unit belongs to the value, not the
  # name, because the reader's unit may not be the stored one.
  # A decision's headline in the reader's units.
  #
  # Progression decisions before rule_version 4.0.0 recorded the weight in the
  # sentence — "Deload to 85 kg" — and every view that printed it raw showed
  # kilograms to an imperial reader, including this page's own heading, above a
  # table rendering the same number in pounds. Those decisions are immutable and
  # stay as they are, so the sentence is rebuilt from the weights beside it.
  # Newer ones carry no measurement and pass straight through.
  def decision_headline(decision)
    return progression_headline(decision.output) if decision.decision_type == "double_progression"

    decision.output["headline"]
  end

  def decision_field_label(key)
    label = key.to_s
    MEASUREMENT_SUFFIXES.each { |suffix| label = label.delete_suffix(suffix) }
    label.humanize
  end

  # A single scalar from a snapshot, in the reader's units where the key says
  # what it measures.
  def decision_field_value(key, value)
    return "—" if value.nil? || value == ""
    return value ? "Yes" : "No" if value == true || value == false

    name = key.to_s
    case name
    when "source" then SOURCE_LABELS.fetch(value.to_s) { value.to_s.humanize }
    when /_kg\z/ then weight(value)
    when /_cm\z/ then length(value)
    when /(\A|_)distance_meters\z/, /_meters\z/ then distance(value)
    when /_seconds_per_km\z/ then pace(value)
    when /_g\z/ then "#{value} g"
    when /_kcal\z/, /\Akcal\z/ then "#{value} kcal"
    when /_ms\z/ then "#{value} ms"
    when /_bpm\z/ then "#{value} bpm"
    when /_minutes\z/ then "#{value} min"
    when /_(at)\z/ then decision_timestamp(value)
    when /_(date|on)\z/ then decision_date(value)
    else value.to_s
    end
  end

  def decision_date(value)
    Date.parse(value.to_s).strftime("%b %-d, %Y")
  rescue Date::Error
    value.to_s
  end

  def decision_timestamp(value)
    Time.zone.parse(value.to_s).strftime("%b %-d, %Y at %H:%M")
  rescue ArgumentError, TypeError
    value.to_s
  end

  # A snapshot stores ids, not associations, so a decision stays readable after
  # the rows around it change. That makes for an unreadable page unless the view
  # resolves them back. Returns nil when the referenced record is gone — which is
  # exactly the case a deleted workout creates — so the caller falls back to the
  # raw id rather than pretending the reference still resolves.
  def decision_reference(key, value)
    return if value.blank?

    case key.to_s
    when "exercise_id"
      exercise = Exercise.available_to(Current.user).find_by(id: value)
      link_to(exercise.name, exercise_path(exercise)) if exercise
    when "workout_session_id"
      session = Current.user.workout_sessions.find_by(id: value)
      return unless session

      label = session.template_name.presence || "Session on #{session.performed_at.to_date.strftime('%b %-d, %Y')}"
      link_to(label, workout_session_path(session))
    when /decision_ids?\z/
      decision_link(value)
    end
  end

  # A decision resting on other decisions is the whole point of the table, and
  # this page is where somebody follows that chain. It used to print the id and
  # stop — "Readiness decision: 168" — leaving the reader to paste a number into
  # a URL to answer the question the page exists to answer.
  #
  # Matched by key shape rather than by listing every one, because the snapshot
  # partial assumes nothing about shape and a new rule should need no work here.
  # Scoped to this account: another account's id resolves to nothing and falls
  # back to the raw value, like any other reference that no longer points
  # anywhere.
  def decision_link(id)
    decision = Current.user.coaching_decisions.find_by(id: id)
    return unless decision

    label = decision_type_label(decision.decision_type)
    headline = decision_headline(decision).to_s.truncate(48)
    link_to(headline.present? ? "#{label}: #{headline}" : label, coaching_decision_path(decision))
  end

  # An array of plain scalars reads better inline than as a nested list.
  def scalar_list?(value)
    value.is_a?(Array) && value.none? { |item| item.is_a?(Hash) || item.is_a?(Array) }
  end
end
