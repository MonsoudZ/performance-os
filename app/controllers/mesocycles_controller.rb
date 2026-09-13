class MesocyclesController < ApplicationController
  include TrainingRecomputable

  before_action :set_mesocycle, only: :finish

  def index
    load_index
  end

  def create
    @mesocycle = Current.user.mesocycles.new(mesocycle_params)

    if @mesocycle.valid?
      # One block runs at a time; starting a new one retires the current one.
      ApplicationRecord.transaction do
        close_active_mesocycle(@mesocycle.started_on)
        @mesocycle.save!
      end
      # Targets are composed against the block rather than rewritten to it, so
      # this recompute is the whole of "applying" a new focus.
      recompute_training_plan
      redirect_to mesocycles_path, notice: "Training block started."
    else
      load_index
      render :index, status: :unprocessable_entity
    end
  end

  def finish
    @mesocycle.update!(ended_on: @mesocycle.ended_on_for(Current.user.local_date))
    recompute_training_plan
    redirect_to mesocycles_path, notice: "Training block ended."
  end

  private

  def set_mesocycle
    @mesocycle = Current.user.mesocycles.find(params[:id])
  end

  def load_index
    @mesocycles = Current.user.mesocycles.order(started_on: :desc, id: :desc)
    @active = Current.user.mesocycles.active_on(Current.user.local_date).order(started_on: :desc).first
    @suggestion = NextBlockSuggestion.new(Current.user).call
    @mesocycle ||= @suggestion || Current.user.mesocycles.new(started_on: Current.user.local_date, weeks: 4, deload_week: 4)
  end

  def close_active_mesocycle(new_start)
    Current.user.mesocycles.active.find_each do |block|
      block.update!(ended_on: block.ended_on_for(new_start))
    end
  end

  def mesocycle_params
    params.require(:mesocycle).permit(:name, :started_on, :weeks, :deload_week, :focus)
  end
end
