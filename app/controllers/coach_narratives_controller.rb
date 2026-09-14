class CoachNarrativesController < ApplicationController
  def create
    unless CoachNarrator.configured?
      redirect_to root_path, alert: "The AI coach isn't configured yet." and return
    end

    # Every narrative is a paid call to Claude, which makes this the one surface
    # where an unconfirmed address costs real money rather than a table row.
    if EmailVerificationsMailer.enforced? && !Current.user.verified?
      redirect_to root_path, alert: "Confirm your email address to ask the coach." and return
    end

    decision = todays_decision
    unless decision
      redirect_to root_path, alert: "Complete today's check-in before asking the coach." and return
    end

    # Claimed rather than checked, so the count and the insert cannot be split by
    # two questions asked at once. A nil back means the day is spent.
    narrative = budget.claim { build_narrative(decision) }
    unless narrative
      redirect_to root_path, alert: budget_spent_message and return
    end

    if narrative.persisted?
      CoachNarrativeJob.perform_later(narrative)
      redirect_to root_path
    else
      redirect_to root_path, alert: narrative.errors.full_messages.to_sentence
    end
  end

  private

  def budget = @budget ||= CoachBudget.new(Current.user)

  # A rejected question is not saved, so it does not spend the slot it was
  # claimed under — the claim only holds for the length of the insert.
  def build_narrative(decision)
    Current.user.coach_narratives.build(
      question: params.dig(:coach_narrative, :question).to_s.strip,
      coaching_decision: decision,
      status: "pending"
    ).tap(&:save)
  end

  def budget_spent_message
    "That's all #{CoachBudget::DAILY_LIMIT} questions for today. The coach resets at midnight."
  end

  def todays_decision
    today = Current.user.local_date
    Current.user.coaching_decisions
      .active_evidence
      .of_type("daily_training")
      .for_input("plan_date", today.iso8601)
      .latest_first
      .first
  end
end
