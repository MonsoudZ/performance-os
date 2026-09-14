# Turns a workout somebody has already logged into a template they can run again.
#
# Building a workout by hand and logging one are the same act done twice: the
# exercises, and the order they were done in, are already in the session. This
# reads them back out so the second time costs a name and a button.
class WorkoutTemplateFromSession
  def initialize(workout_session, name: nil)
    @workout_session = workout_session
    @name = name.to_s.strip.presence || self.class.suggested_name(workout_session)
  end

  # What to put in the field before the user touches it. A session logged from a
  # template is almost always that workout again, so it keeps the name — with a
  # counter when that name is already taken, because the common case (running the
  # same template twice and saving the second one) would otherwise be a
  # validation error on a name the user never typed.
  def self.suggested_name(workout_session)
    base = workout_session.template_name.presence ||
      workout_session.performed_at.strftime("%A workout")
    taken = workout_session.user.workout_templates.pluck(:name)
    return base unless taken.include?(base)

    (2..).each { |suffix| return "#{base} #{suffix}" unless taken.include?("#{base} #{suffix}") }
  end

  def call
    template = user.workout_templates.new(name: name)

    exercise_ids.each_with_index do |exercise_id, index|
      template.workout_template_exercises.build(exercise_id: exercise_id, position: index + 1)
    end

    template.save
    template
  end

  private

  attr_reader :workout_session, :name

  def user = workout_session.user

  # In the order they were performed, each exercise once. Warm-ups alone do not
  # make an exercise part of the workout — you did not train it — but a session
  # that was nothing but warm-ups is still worth saving as what it was.
  def exercise_ids
    sets = workout_session.set_entries.sort_by { |entry| [ entry.set_index, entry.id ] }
    working = sets.reject(&:is_warmup?)

    (working.presence || sets).map(&:exercise_id).uniq
  end
end
