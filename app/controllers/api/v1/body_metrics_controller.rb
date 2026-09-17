module Api
  module V1
    # Weighing in, and what the app makes of a run of weigh-ins.
    #
    # A weigh-in is the evidence behind the calorie target: it feeds the weight
    # trend, the trend feeds the adaptive expenditure estimate, and that feeds
    # `NutritionTargetResolver`. So a write here recomputes the day, the same way
    # the web does, rather than leaving the targets describing an older body.
    class BodyMetricsController < BaseController
      DEFAULT_LIMIT = 30
      MAX_LIMIT = 180

      def index
        render json: {
          data: BodyCompositionSerializer.new(
            metrics: current_user.body_metrics.order(measured_on: :desc, id: :desc).limit(limit),
            trends: current_user.weight_trends.order(trend_date: :desc).limit(limit),
            expenditure: current_user.expenditure_estimates.order(estimate_date: :desc).first
          ).as_json
        }
      end

      def create
        body_metric = current_user.body_metrics.new(body_metric_params)

        if body_metric.save
          BodyMetricRecomputeJob.perform_later(current_user, body_metric.measured_on)
          render json: { data: BodyMetricSerializer.new(body_metric).as_json }, status: :created
        else
          render json: { error: "Invalid weigh-in", details: body_metric.errors.full_messages },
            status: :unprocessable_entity
        end
      end

      def destroy
        body_metric = current_user.body_metrics.find(params[:id])
        measured_on = body_metric.measured_on
        body_metric.destroy!
        # The EWMA chain is walked forward from the removed day, so the trend
        # re-derives without it rather than leaving stale rows downstream.
        BodyMetricRecomputeJob.perform_later(current_user, measured_on)

        head :no_content
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      private

      # The weight is stored exactly as it arrives — kilograms, unconverted, like
      # every measurement on this boundary. The web form's converter is for a
      # form, which posts whatever unit it displayed. Body fat needs no
      # conversion in either direction: a percentage is the same number to
      # everybody.
      #
      # `source` is not accepted from the client, and that is a rule rather than
      # an omission: a row claiming "healthkit" is one the next sync will
      # overwrite, because `WearableBodyMassMaterializer` finds its row by
      # (date, source) and re-derives it. A weight somebody typed must be a row
      # nothing else owns.
      def body_metric_params
        params.require(:body_metric)
          .permit(:measured_on, :weight_kg, :body_fat_pct)
          .with_defaults(measured_on: current_user.local_date)
          .merge(source: "manual")
      end

      def limit
        params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      end
    end
  end
end
