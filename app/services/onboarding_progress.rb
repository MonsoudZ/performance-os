# What a new account still has to do before the engine can say anything useful,
# and how far along they are.
#
# This exists as one object because two places need the same answer: the
# onboarding page, and the dashboard, which has to surface the remaining steps —
# nothing links back to onboarding once a user has left it, so a dashboard that
# stayed quiet would leave them with no way to find out what is missing.
class OnboardingProgress
  Step = Data.define(:key, :title, :prompt, :cta, :path, :done, :optional) do
    def done? = done
    def optional? = optional
  end

  def initialize(user, routes: Rails.application.routes.url_helpers)
    @user = user
    @routes = routes
  end

  def steps
    @steps ||= [ goal_step, target_step, check_in_step, device_step ]
  end

  # The two that gate a plan. A watch is genuinely optional, and a user who has
  # checked in has a plan even without targets, so neither blocks "set up".
  def complete?
    goal_step.done? && (target_step.done? || check_in_step.done?)
  end

  # What to point at next: the first required step still outstanding.
  def next_step
    remaining.first
  end

  def remaining
    steps.reject { |step| step.done? || step.optional? }
  end

  private

  attr_reader :user, :routes

  def goal
    return @goal if defined?(@goal)

    @goal = user.active_goal
  end

  def goal_step
    @goal_step ||= Step.new(
      key: :goal,
      title: "Set your training goal",
      prompt: goal ? "You're training for #{goal.goal_type.humanize.downcase}." :
        "Your goal drives calorie, protein, and training targets.",
      cta: goal ? "Change goal" : "Set a goal",
      path: routes.goal_periods_path,
      done: goal.present?,
      optional: false
    )
  end

  def target_step
    done = user.exercise_prescriptions.exists?
    @target_step ||= Step.new(
      key: :target,
      title: "Add a training target",
      prompt: done ? "The engine knows what to progress." :
        "Progression has nothing to advance until a lift has a rep, RIR and load target.",
      cta: done ? "Manage targets" : "Add a target",
      path: done ? routes.exercise_prescriptions_path : routes.new_exercise_prescription_path,
      done: done,
      optional: false
    )
  end

  def check_in_step
    done = user.daily_readiness_inputs.exists?
    @check_in_step ||= Step.new(
      key: :check_in,
      title: "Do your first check-in",
      prompt: done ? "Readiness is feeding the plan." :
        "Sixty seconds of recovery inputs generates today's plan.",
      cta: done ? "Review check-ins" : "Check in",
      path: done ? routes.readiness_inputs_path : routes.root_path,
      done: done,
      optional: false
    )
  end

  def device_step
    done = user.wearable_devices.active.exists?
    @device_step ||= Step.new(
      key: :device,
      title: "Pair your watch",
      prompt: done ? "HRV, resting heart rate and sleep are syncing." :
        "Auto-fill HRV, resting heart rate and sleep from HealthKit.",
      cta: "Manage devices",
      path: routes.wearable_devices_path,
      done: done,
      optional: true
    )
  end
end
