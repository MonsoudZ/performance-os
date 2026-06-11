# Turns the active goal, today's readiness, and the week's conditioning progress
# into a single conditioning recommendation for the daily plan. Pure function of
# its inputs — no DB writes; the orchestrator composes the result into the
# daily_training decision.
class ConditioningDirective
  # Per-goal weekly conditioning emphasis and target.
  GOALS = {
    "marathon"             => { metric: :distance, target: 40,  label: "weekly km",       emphasis: :endurance },
    "longevity"            => { metric: :zone2,    target: 150, label: "Zone 2 minutes",  emphasis: :base },
    "athletic_performance" => { metric: :sessions, target: 3,   label: "sessions",         emphasis: :mixed },
    "vertical_jump"        => { metric: :sessions, target: 2,   label: "power sessions",    emphasis: :power },
    "build_muscle"         => { metric: :zone2,    target: 60,  label: "Zone 2 minutes",   emphasis: :recovery },
    "increase_strength"    => { metric: :zone2,    target: 60,  label: "Zone 2 minutes",   emphasis: :recovery }
  }.freeze
  DEFAULT = { metric: :zone2, target: 90, label: "Zone 2 minutes", emphasis: :base }.freeze

  SESSION = {
    endurance: { steady: "a steady-state run", quality: "a long run or tempo effort" },
    base:      { steady: "an easy Zone 2 session", quality: "a longer Zone 2 session" },
    power:     { steady: "technical jump work", quality: "max-intent jumps or plyometrics" },
    mixed:     { steady: "moderate conditioning", quality: "intervals or a tempo effort" },
    recovery:  { steady: "optional easy Zone 2", quality: "optional easy Zone 2" }
  }.freeze

  def initialize(goal:, readiness_status:, summary:)
    @goal = goal
    @readiness_status = readiness_status
    @summary = summary
  end

  def call
    focus, headline, guidance = recommendation

    {
      "focus" => focus,
      "headline" => headline,
      "guidance" => guidance,
      "metric" => config[:metric].to_s,
      "label" => config[:label],
      "done" => done,
      "target" => config[:target]
    }
  end

  private

  attr_reader :goal, :readiness_status, :summary

  def config
    @config ||= GOALS.fetch(goal&.goal_type, DEFAULT)
  end

  def done
    @done ||= case config[:metric]
    when :distance then summary.total_distance_km
    when :zone2 then summary.zone2_minutes
    else summary.session_count
    end
  end

  def on_track?
    done >= config[:target]
  end

  def progress_note
    "You're at #{done} of #{config[:target]} #{config[:label]} this week."
  end

  def recommendation
    case readiness_status
    when "recover" then recovery_recommendation
    when "steady" then steady_recommendation
    else push_recommendation
    end
  end

  def recovery_recommendation
    if on_track?
      [ "recovery", "Optional easy movement", "#{progress_note} Readiness is low and the target is met — rest or an easy walk today." ]
    else
      [ "recovery", "Keep it to Zone 2", "Readiness is low. If you do anything, keep it to easy Zone 2 — no intervals or long efforts today." ]
    end
  end

  def steady_recommendation
    if on_track?
      [ "maintain", "Hold steady", "#{progress_note} You've hit the target, so an easy session is plenty." ]
    else
      [ "steady", "Get #{SESSION[config[:emphasis]][:steady]} in", "#{progress_note} A steady session today keeps you on pace." ]
    end
  end

  def push_recommendation
    if on_track?
      [ "optional", "Quality optional", "#{progress_note} Target met — a quality session is fine if you want it, not required." ]
    else
      [ "quality", "Go for #{SESSION[config[:emphasis]][:quality]}", "#{progress_note} Readiness is high — a quality session moves you toward the target." ]
    end
  end
end
