class StrengthProgression
  Point = Data.define(:date, :e1rm, :pr)
  ExerciseProgress = Data.define(:exercise, :points, :current_e1rm, :best_e1rm, :pr_count, :last_pr_on)

  def initialize(user)
    @user = user
  end

  def call
    grouped = session_bests.group_by { |row| row.fetch(:exercise_id) }
    exercises = Exercise.where(id: grouped.keys).index_by(&:id)

    grouped.filter_map do |exercise_id, rows|
      exercise = exercises[exercise_id]
      next unless exercise

      build_progress(exercise, rows.sort_by { |row| row.fetch(:performed_at) })
    end.sort_by { |progress| progress.exercise.name }
  end

  private

  attr_reader :user

  # Best estimated 1RM (Epley, stored column) per session per exercise.
  def session_bests
    SetEntry
      .joins(:workout_session)
      .where(workout_sessions: { user_id: user.id })
      .where(is_warmup: false)
      .where.not(estimated_1rm_kg: nil)
      .group(:exercise_id, "workout_sessions.performed_at")
      .maximum(:estimated_1rm_kg)
      .map { |(exercise_id, performed_at), e1rm| { exercise_id:, performed_at:, e1rm: e1rm.to_f } }
  end

  def build_progress(exercise, rows)
    best_so_far = nil
    pr_count = 0
    last_pr_on = nil

    points = rows.map do |row|
      e1rm = row.fetch(:e1rm).round(1)
      # The first session is a baseline; later sessions that beat the running
      # best are PRs.
      pr = !best_so_far.nil? && e1rm > best_so_far + 0.01
      if pr
        pr_count += 1
        last_pr_on = row.fetch(:performed_at).to_date
      end
      best_so_far = best_so_far.nil? ? e1rm : [ best_so_far, e1rm ].max
      Point.new(date: row.fetch(:performed_at).to_date, e1rm: e1rm, pr: pr)
    end

    ExerciseProgress.new(
      exercise: exercise,
      points: points,
      current_e1rm: points.last.e1rm,
      best_e1rm: best_so_far.round(1),
      pr_count: pr_count,
      last_pr_on: last_pr_on
    )
  end
end
