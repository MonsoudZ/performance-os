class ProgressController < ApplicationController
  def show
    weekly = WeeklyMuscleVolume.new(Current.user)
    @week_start = weekly.week_start
    @week_end = weekly.week_end
    @volume = weekly.call
    @progress = StrengthProgression.new(Current.user).call
    @weight_trend = Current.user.weight_trends.order(:trend_date).last(30)
    @readiness_trend = Current.user.readiness_scores.order(:score_date).last(30)
  end
end
