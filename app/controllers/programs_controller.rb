class ProgramsController < ApplicationController
  include TrainingRecomputable

  # Generate a starting program from the active goal, then recompute today's
  # plan so the dashboard reflects the new targets.
  def create
    result = ProgramGenerator.new(Current.user).call

    if result.goal.nil?
      redirect_to goal_periods_path, alert: "Set a training goal first — it drives the program."
    elsif result.created_any?
      recompute_training_plan
      redirect_to exercise_prescriptions_path,
        notice: "Built a #{result.focus} starting program: #{result.created.size} #{'lift'.pluralize(result.created.size)} you can tweak below."
    else
      redirect_to exercise_prescriptions_path,
        notice: "Your program already covers the main lifts — nothing to add."
    end
  end

  # Refresh the program against the current profile: retire lifts the user can
  # no longer do (equipment changed) and add the now-possible replacements.
  def update
    result = ProgramGenerator.new(Current.user, prune_unavailable: true).call

    if result.goal.nil?
      redirect_to goal_periods_path, alert: "Set a training goal first — it drives the program."
    elsif result.changed_any?
      recompute_training_plan
      redirect_to exercise_prescriptions_path, notice: refresh_notice(result)
    else
      redirect_to exercise_prescriptions_path, notice: "Your program already matches your profile."
    end
  end

  private

  def refresh_notice(result)
    parts = []
    parts << "added #{result.created.size} #{'lift'.pluralize(result.created.size)}" if result.created_any?
    parts << "retired #{result.retired.size} you can no longer do" if result.retired_any?
    "Refreshed your program: #{parts.join(' and ')}."
  end
end
