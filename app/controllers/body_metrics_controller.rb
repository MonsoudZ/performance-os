class BodyMetricsController < ApplicationController
  def create
    body_metric = Current.user.body_metrics.new(body_metric_params)

    if body_metric.save
      BodyMetricRecomputeJob.perform_later(Current.user, body_metric.measured_on)
      redirect_to nutrition_path, notice: "Body weight logged. Updating your targets…"
    else
      redirect_to nutrition_path, alert: body_metric.errors.full_messages.to_sentence
    end
  end

  def destroy
    body_metric = Current.user.body_metrics.find(params[:id])
    date = body_metric.measured_on
    body_metric.destroy!
    BodyMetricRecomputeJob.perform_later(Current.user, date)
    redirect_to nutrition_path, notice: "Weigh-in removed."
  end

  private

  def body_metric_params
    params.require(:body_metric).permit(:measured_on, :weight_kg)
  end
end
