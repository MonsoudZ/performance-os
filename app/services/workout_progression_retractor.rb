class WorkoutProgressionRetractor
  def initialize(workout_session, reason:)
    @workout_session = workout_session
    @reason = reason
  end

  def call
    queue = workout_session.user.coaching_decisions
      .active_evidence
      .of_type("double_progression")
      .for_input("workout_session_id", workout_session.id)
      .to_a
    visited_ids = Set.new

    until queue.empty?
      decision = queue.shift
      next unless visited_ids.add?(decision.id)

      queue.concat(decision.parent_decisions.active_evidence.to_a)
      decision.retract!(reason:)
    end
  end

  private

  attr_reader :workout_session, :reason
end
