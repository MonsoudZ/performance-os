class WeeklyMuscleVolume
  Entry = Data.define(:muscle, :fractional_sets, :landmark, :status)

  def initialize(user, week_start: nil)
    @user = user
    @week_start = week_start || user.local_date.beginning_of_week # Monday
  end

  def call
    volume_by_muscle.map do |name, fractional_sets|
      landmark = MuscleGroup::LANDMARKS[name]
      Entry.new(
        muscle: name,
        fractional_sets: fractional_sets.to_f.round(1),
        landmark: landmark,
        status: status_for(fractional_sets.to_f, landmark)
      )
    end.sort_by { |entry| -entry.fractional_sets }
  end

  def week_start = @week_start
  def week_end = @week_start + 6.days

  private

  attr_reader :user

  # Each performed working set contributes its exercise's fraction (1.0 primary,
  # 0.5 secondary) to every muscle it trains; summing the fractions gives
  # fractional sets per muscle for the week.
  def volume_by_muscle
    SetEntry
      .joins(:workout_session, exercise: { exercise_muscle_contributions: :muscle_group })
      .where(workout_sessions: { user_id: user.id, performed_at: week_range })
      .where(is_warmup: false)
      .where.not(reps: nil)
      .group("muscle_groups.name")
      .sum("exercise_muscle_contributions.fraction")
  end

  def week_range
    user.local_day_range(week_start).begin..user.local_day_range(week_end).end
  end

  def status_for(volume, landmark)
    return "untracked" unless landmark
    return "under" if volume < landmark[:mev]
    return "over" if volume > landmark[:mrv]

    "in_range"
  end
end
