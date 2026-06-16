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
end
