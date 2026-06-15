class GoalPeriodsController < ApplicationController
  include NutritionRecomputable

  def index
    load_index
  end

  def create
    @goal_period = Current.user.goal_periods.new(goal_period_attributes)

    if @goal_period.valid?
      # Only one goal may be active at a time (enforced by a partial unique
      # index), so retire the current one before the new one opens.
      ApplicationRecord.transaction do
        close_active_goal(@goal_period.started_on)
        @goal_period.save!
      end
      recompute_nutrition
      redirect_to goal_periods_path, notice: "Goal set to #{@goal_period.goal_type.humanize.downcase}."
    else
      load_index
      render :index, status: :unprocessable_entity
    end
  end

  def finish
    goal = Current.user.goal_periods.find(params[:id])
    # End dates are inclusive, so "no longer active today" means the last active
    # day was yesterday (or the start date for a goal opened today).
    goal.update!(ended_on: [ Current.user.local_date - 1.day, goal.started_on ].max)
    recompute_nutrition
    redirect_to goal_periods_path, notice: "Goal ended."
  end

  private

  def load_index
    @goal_periods = Current.user.goal_periods.order(started_on: :desc, id: :desc)
    @active_goal = Current.user.goal_periods.active_on(Current.user.local_date).order(started_on: :desc).first
    @goal_period ||= Current.user.goal_periods.new(
      goal_type: "build_muscle",
      started_on: Current.user.local_date
    )
  end

  def close_active_goal(new_start)
    Current.user.goal_periods.active.find_each do |goal|
      goal.update!(ended_on: [ new_start - 1.day, goal.started_on ].max)
    end
  end

  def goal_period_attributes
    permitted = params.require(:goal_period).permit(:goal_type, :started_on, :target_kcal, :target_protein_g)
    {
      goal_type: permitted[:goal_type],
      started_on: permitted[:started_on],
      params: explicit_targets(permitted)
    }
  end

  def explicit_targets(permitted)
    {}.tap do |targets|
      targets["target_kcal"] = permitted[:target_kcal].to_i if permitted[:target_kcal].present?
      targets["target_protein_g"] = permitted[:target_protein_g].to_i if permitted[:target_protein_g].present?
    end
  end
end
