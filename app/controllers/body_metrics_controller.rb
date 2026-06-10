class BodyMetricsController < ApplicationController
  def create
    body_metric = Current.user.body_metrics.new(body_metric_params)

    if body_metric.save
      BodyMetricRecomputeJob.perform_later(body_metric)
      redirect_to nutrition_path, notice: "Body weight logged. Updating your targets…"
    else
      redirect_to nutrition_path, alert: body_metric.errors.full_messages.to_sentence
    end
  end

  private

  def body_metric_params
    params.require(:body_metric).permit(:measured_on, :weight_kg)
  end
end
