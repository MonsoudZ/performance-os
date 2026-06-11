class ProgressController < ApplicationController
  def show
    weekly = WeeklyMuscleVolume.new(Current.user)
    @week_start = weekly.week_start
    @week_end = weekly.week_end
    @volume = weekly.call
    @progress = StrengthProgression.new(Current.user).call
  end
end
