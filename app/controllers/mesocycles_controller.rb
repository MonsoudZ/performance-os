class MesocyclesController < ApplicationController
  include TrainingRecomputable

  before_action :set_mesocycle, only: %i[finish apply_scheme]

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
        apply_scheme_to_targets(@mesocycle.focus) if params[:apply_scheme] == "1"
      end
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

  def apply_scheme
    count = apply_scheme_to_targets(@mesocycle.focus)
    recompute_training_plan
    redirect_to exercise_prescriptions_path,
      notice: "Applied the #{@mesocycle.focus} rep scheme to #{helpers.pluralize(count, 'target')}."
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

  def apply_scheme_to_targets(focus)
    ApplyBlockScheme.new(Current.user, focus: focus).call
  end

  def mesocycle_params
    params.require(:mesocycle).permit(:name, :started_on, :weeks, :deload_week, :focus)
  end
end
