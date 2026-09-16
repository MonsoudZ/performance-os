class ReadinessInputsController < ApplicationController
  before_action :set_input, only: %i[edit update]

  def index
    @inputs = Current.user.daily_readiness_inputs.order(metric_date: :desc).limit(30)
    @scores = Current.user.readiness_scores.index_by(&:score_date)
  end

  def edit
  end

  def update
    @input.assign_attributes(readiness_params)
    # Answering a day the watch had synced makes it a row holding both kinds of
    # evidence; leaving `source` alone left it reading "healthkit" while
    # `checked_in?` said the user had answered it.
    @input.source = @input.derived_source

    if @input.save
      ReadinessRecomputeJob.perform_later(@input)
      redirect_to readiness_inputs_path, notice: "Check-in for #{@input.metric_date.strftime("%b %-d")} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_input
    @input = Current.user.daily_readiness_inputs.find(params[:id])
  end

  def readiness_params
    params.require(:daily_readiness_input).permit(:sleep_hours, :sleep_quality, :soreness, :fatigue, :stress)
  end
end
