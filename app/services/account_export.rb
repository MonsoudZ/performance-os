# Everything the app holds on one account, as a single JSON document.
#
# The spec is the complement of AccountDeletion: whatever erasure destroys, this
# hands back first. `AccountExportTest` cross-references the two so a new
# association cannot be added to one without the other noticing.
#
# Two deliberate departures from that symmetry:
#
#   - **Credentials are never exported**, even though deletion removes them. A
#     password digest and a device's bearer-token digest are how the account is
#     secured, not facts about the user, and a file they might email to
#     themselves is the last place either belongs.
#   - **Referenced catalog exercises are exported**, even though they belong to
#     nobody and deletion leaves them alone. Without them a set entry is a weight
#     against an integer, and the export cannot be read.
#
# Values stay in the units the database stores — kilograms, centimetres, metres —
# for the same reason decision prose does: this is a record of what was written,
# not a rendering of it. The header says so, and carries the reader's own unit
# system so the numbers can be converted with confidence.
class AccountExport
  FORMAT_VERSION = "1.0".freeze

  # Secrets, not data. Excluded from every section by name, so a column added to
  # any table cannot quietly export one.
  # `api_token_digest` is named separately from `token_digest`: `except:` matches
  # a column name exactly, so the wearable device's exclusion does not cover the
  # session's, and a native token would have ridden out in the file.
  EXCLUDED_COLUMNS = %w[password_digest token_digest api_token_digest p256dh_key auth_key].freeze

  def initialize(user)
    @user = user
  end

  def filename
    "performance-os-export-#{user.local_date.iso8601}.json"
  end

  def to_json(*)
    JSON.pretty_generate(call)
  end

  def call
    {
      "export" => header,
      "profile" => rows(User.where(id: user.id)).first,
      "goal_periods" => rows(user.goal_periods),
      "mesocycles" => rows(user.mesocycles),
      "exercises" => rows(referenced_exercises),
      "exercise_prescriptions" => rows(user.exercise_prescriptions),
      "workout_templates" => workout_templates,
      "workout_sessions" => workout_sessions,
      "conditioning_sessions" => rows(user.conditioning_sessions),
      "daily_readiness_inputs" => rows(user.daily_readiness_inputs),
      "readiness_scores" => rows(user.readiness_scores),
      "body_metrics" => rows(user.body_metrics),
      "weight_trends" => rows(user.weight_trends),
      "expenditure_estimates" => rows(user.expenditure_estimates),
      "foods" => rows(user.foods),
      "meals" => meals,
      "food_log_entries" => rows(user.food_log_entries),
      "wearable_devices" => rows(user.wearable_devices),
      "wearable_samples" => rows(user.wearable_samples),
      "coaching_decisions" => coaching_decisions,
      "coach_narratives" => rows(user.coach_narratives),
      "push_subscriptions" => rows(user.push_subscriptions),
      "sessions" => rows(user.sessions)
    }
  end

  private

  attr_reader :user

  def header
    {
      "format_version" => FORMAT_VERSION,
      "generated_at" => Time.current.iso8601,
      "units" => {
        "weight" => "kilograms",
        "length" => "centimetres",
        "distance" => "metres",
        "note" => "Stored units, not display units. Your account reads in " \
          "#{user.unit_system}; converting is a factor, never a re-measurement."
      }
    }
  end

  def rows(relation)
    relation.order(:id).as_json(except: EXCLUDED_COLUMNS)
  end

  # Every exercise the account's own records point at, its custom ones included.
  # Catalog lifts are shared and survive deletion, but without them the ids in
  # prescriptions, templates and set entries resolve to nothing.
  def referenced_exercises
    Exercise.where(id: user.exercises.select(:id))
      .or(Exercise.where(id: user.exercise_prescriptions.select(:exercise_id)))
      .or(Exercise.where(id: SetEntry.where(workout_session_id: user.workout_sessions.select(:id)).select(:exercise_id)))
      .or(Exercise.where(id: WorkoutTemplateExercise.where(workout_template_id: user.workout_templates.select(:id)).select(:exercise_id)))
  end

  def workout_templates
    user.workout_templates.order(:id).includes(:workout_template_exercises).map do |template|
      rows(WorkoutTemplate.where(id: template.id)).first.merge(
        "exercises" => rows(template.workout_template_exercises)
      )
    end
  end

  # Set entries hang off their session and are reachable nowhere else, so they
  # are nested rather than given a section of their own.
  # Items hang off their meal and are reachable nowhere else, so they nest rather
  # than forming a section of their own — the same shape as a session's sets.
  def meals
    user.meals.order(:id).includes(:meal_items).map do |meal|
      rows(Meal.where(id: meal.id)).first.merge("meal_items" => rows(meal.meal_items))
    end
  end

  def workout_sessions
    user.workout_sessions.order(:id).includes(:set_entries).map do |session|
      rows(WorkoutSession.where(id: session.id)).first.merge(
        "set_entries" => rows(session.set_entries)
      )
    end
  end

  # The links are the product's central claim made portable: a decision on its
  # own says what was recommended, and the citations say what it was built from.
  def coaching_decisions
    links = CoachingDecisionLink
      .where(parent_decision_id: user.coaching_decisions.select(:id))
      .group_by(&:parent_decision_id)

    user.coaching_decisions.order(:id).map do |decision|
      rows(CoachingDecision.where(id: decision.id)).first.merge(
        "cites" => links.fetch(decision.id, []).map do |link|
          { "decision_id" => link.child_decision_id, "role" => link.role }
        end
      )
    end
  end
end
