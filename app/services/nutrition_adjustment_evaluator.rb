class NutritionAdjustmentEvaluator
  RULE_KEY = "nutrition_adjustment.v1"
  RULE_VERSION = "1.0.0"
  CALORIE_STEP = 150
  MINIMUM_REVIEW_CADENCE_DAYS = 7

  def initialize(weekly_review)
    @weekly_review = weekly_review
    @user = weekly_review.user
  end

  def call
    return current_decision if current_decision

    ApplicationRecord.transaction do
      decision = user.coaching_decisions.create!(
        decision_type: "nutrition_adjustment",
        rule_key: RULE_KEY,
        rule_version: RULE_VERSION,
        inputs: inputs,
        output: output,
        citations: [],
        confidence: weekly_review.confidence
      )
      decision.child_links.create!(child_decision: weekly_review, role: "weekly_review")
      decision
    end
  end

  private

  attr_reader :weekly_review, :user

  def current_decision
    @current_decision ||= user.coaching_decisions
      .where(decision_type: "nutrition_adjustment", rule_key: RULE_KEY)
      .where("inputs ->> 'weekly_review_decision_id' = ?", weekly_review.id.to_s)
      .order(created_at: :desc)
      .first
  end

  def active_goal
    @active_goal ||= user.goal_periods
      .where("started_on <= ? AND (ended_on IS NULL OR ended_on >= ?)", period_end, period_end)
      .order(started_on: :desc)
      .first
  end

  def current_target
    @current_target ||= NutritionTargetResolver.new(user, goal: active_goal, target_date: period_end).call["kcal"]
  end

  def direction
    return "cadence_locked" if correction_too_soon?

    weekly_review.output["calorie_direction"]
  end

  def calorie_delta
    case direction
    when "increase" then CALORIE_STEP
    when "decrease" then -CALORIE_STEP
    else 0
    end
  end

  def new_target
    current_target ? current_target.to_f + calorie_delta : nil
  end

  def period_end
    Date.iso8601(weekly_review.output.dig("period", "end"))
  end

  def effective_on
    period_end + 1.day
  end

  def inputs
    {
      "weekly_review_decision_id" => weekly_review.id,
      "goal_period_id" => active_goal&.id,
      "current_target_kcal" => current_target,
      "previous_adjustment_decision_id" => previous_adjustment&.id
    }
  end

  def output
    {
      "status" => direction,
      "headline" => headline,
      "guidance" => guidance,
      "calorie_delta" => calorie_delta,
      "previous_target_kcal" => current_target,
      "target_kcal" => new_target,
      "effective_on" => effective_on
    }
  end

  def headline
    case direction
    when "increase" then "Add #{CALORIE_STEP} kcal"
    when "decrease" then "Remove #{CALORIE_STEP} kcal"
    when "hold" then "Keep calories unchanged"
    when "cadence_locked" then "Keep calories unchanged this week"
    else "No calorie correction yet"
    end
  end

  def guidance
    return "No calorie target is available to adjust." unless current_target

    case direction
    when "increase", "decrease"
      "The new #{new_target.round} kcal target begins #{effective_on.strftime("%B %-d")} and remains active until newer weekly evidence replaces it."
    when "hold"
      "The weight trend is inside the goal rate band, so the current target remains in place."
    when "cadence_locked"
      "A calorie correction already used a review from the last seven days. Wait for a new weekly evidence window."
    else
      "Collect the full evidence window before changing calories."
    end
  end

  def correction_too_soon?
    previous_review_end && period_end < previous_review_end + MINIMUM_REVIEW_CADENCE_DAYS.days
  end

  def previous_adjustment
    @previous_adjustment ||= user.coaching_decisions
      .where(decision_type: "nutrition_adjustment", rule_key: RULE_KEY)
      .where.not("output ->> 'calorie_delta' = '0'")
      .where.not(id: current_decision&.id)
      .order(created_at: :desc)
      .first
  end

  def previous_review_end
    return unless previous_adjustment

    review_id = previous_adjustment.inputs["weekly_review_decision_id"]
    review = user.coaching_decisions.find_by(id: review_id, decision_type: "weekly_review")
    Date.iso8601(review.output.dig("period", "end")) if review
  end
end
