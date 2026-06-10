class ReadinessCheckInsController < ApplicationController
  def create
    readiness_input = save_today_check_in

    if readiness_input.persisted? && readiness_input.errors.empty?
      ReadinessRecomputeJob.perform_later(readiness_input)
      redirect_to root_path, notice: "Check-in saved. Generating today’s plan…"
    else
      redirect_to root_path, alert: readiness_input.errors.full_messages.to_sentence
    end
  end

  private

  # A double-submit can race two find_or_initialize_by inserts against the
  # unique (user_id, metric_date) index. Retry once so the loser finds the now
  # existing row and updates it instead of raising an unhandled 500.
  def save_today_check_in
    attempts = 0
    begin
      input = Current.user.daily_readiness_inputs.find_or_initialize_by(metric_date: Current.user.local_date)
      input.assign_attributes(readiness_params)
      input.source = input.hrv_sdnn_ms.present? || input.resting_hr.present? ? "mixed" : "manual"
      input.save
      input
    rescue ActiveRecord::RecordNotUnique
      raise if (attempts += 1) > 1

      retry
    end
  end

  def readiness_params
    params.require(:daily_readiness_input).permit(
      :sleep_minutes,
      :sleep_quality,
      :soreness,
      :fatigue,
      :stress
    )
  end
end
