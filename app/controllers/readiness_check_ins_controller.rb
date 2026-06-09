class ReadinessCheckInsController < ApplicationController
  def create
    readiness_input = Current.user.daily_readiness_inputs.find_or_initialize_by(metric_date: Current.user.local_date)
    readiness_input.assign_attributes(readiness_params)
    readiness_input.source = readiness_input.hrv_sdnn_ms.present? || readiness_input.resting_hr.present? ? "mixed" : "manual"

    if readiness_input.save
      ReadinessEvaluator.new(readiness_input).call
      NutritionEvaluator.new(Current.user).call
      DailyTrainingOrchestrator.new(Current.user).call
      redirect_to root_path, notice: "Check-in saved. Today’s recommendation is ready."
    else
      redirect_to root_path, alert: readiness_input.errors.full_messages.to_sentence
    end
  end

  private

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
