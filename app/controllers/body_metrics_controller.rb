class BodyMetricsController < ApplicationController
  def create
    body_metric = Current.user.body_metrics.new(body_metric_params)

    if body_metric.save
      WeightTrendMaterializer.new(Current.user, trend_date: body_metric.measured_on).call
      ExpenditureEstimator.new(Current.user, estimate_date: body_metric.measured_on).call
      NutritionEvaluator.new(Current.user, nutrition_date: body_metric.measured_on).call
      DailyTrainingOrchestrator.new(Current.user, plan_date: body_metric.measured_on).call if body_metric.measured_on == Current.user.local_date
      redirect_to nutrition_path, notice: "Body weight logged."
    else
      redirect_to nutrition_path, alert: body_metric.errors.full_messages.to_sentence
    end
  end

  private

  def body_metric_params
    params.require(:body_metric).permit(:measured_on, :weight_kg)
  end
end
