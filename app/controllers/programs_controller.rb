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
      redirect_to exercise_prescriptions_path, notice: build_notice(result)
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

  # The focus is not a label on the program — it picks the rep range every lift
  # will run, so the notice says which one, why the goal chose it, and that a
  # block is now the thing setting it.
  def build_notice(result)
    sentences = [
      "Built a #{result.focus} starting program because #{result.focus_reason}: " \
        "#{result.created.size} #{'lift'.pluralize(result.created.size)} you can tweak below."
    ]
    if result.started_block?
      sentences << "A 4-week #{result.focus} block now sets their rep ranges; end it and each target keeps its own."
    end
    sentences.join(" ")
  end

  def refresh_notice(result)
    parts = []
    parts << "added #{result.created.size} #{'lift'.pluralize(result.created.size)}" if result.created_any?
    parts << "retired #{result.retired.size} you can no longer do" if result.retired_any?
    "Refreshed your program: #{parts.join(' and ')}."
  end
end
