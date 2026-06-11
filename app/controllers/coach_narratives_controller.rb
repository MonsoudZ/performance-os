class CoachNarrativesController < ApplicationController
  def create
    unless CoachNarrator.configured?
      redirect_to root_path, alert: "The AI coach isn't configured yet." and return
    end

    decision = todays_decision
    unless decision
      redirect_to root_path, alert: "Complete today's check-in before asking the coach." and return
    end

    narrative = Current.user.coach_narratives.build(
      question: params.dig(:coach_narrative, :question).to_s.strip,
      coaching_decision: decision,
      status: "pending"
    )

    if narrative.save
      CoachNarrativeJob.perform_later(narrative)
      redirect_to root_path
    else
      redirect_to root_path, alert: narrative.errors.full_messages.to_sentence
    end
  end

  private

  def todays_decision
    today = Current.user.local_date
    Current.user.coaching_decisions
      .where(decision_type: "daily_training")
      .where("inputs ->> 'plan_date' = ?", today.iso8601)
      .order(created_at: :desc)
      .first
  end
end
