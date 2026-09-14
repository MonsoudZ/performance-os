# One account that has used every part of the app.
#
# Shared by the two tests that have to agree about what an account *is*:
# AccountDeletion erases all of this, and AccountExport hands all of it back. A
# new association on User belongs in both lists, and leaving it out of either
# fails a test rather than going unnoticed.
module AccountFixture
  # Every model that holds rows belonging to a user. Deletion empties all of
  # them; the export has a section for each.
  ACCOUNT_MODELS = [
    Session, PushSubscription, CoachNarrative, CoachingDecision, ConditioningSession,
    WearableSample, WearableDevice, WorkoutSession, WorkoutTemplate, ExercisePrescription,
    Exercise, FoodLogEntry, Food, GoalPeriod, DailyReadinessInput, ReadinessScore,
    BodyMetric, WeightTrend, ExpenditureEstimate, Mesocycle
  ].freeze

  def populate_account(user)
    user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    user.push_subscriptions.create!(
      endpoint: "https://web.push.apple.com/#{SecureRandom.hex(4)}", p256dh_key: "k", auth_key: "a"
    )
    user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current - 30)
    user.mesocycles.create!(focus: "hypertrophy", started_on: Date.current - 7, weeks: 4)
    user.daily_readiness_inputs.create!(
      metric_date: Date.current, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2
    )
    user.readiness_scores.create!(score_date: Date.current, score: 72)
    user.body_metrics.create!(measured_on: Date.current, weight_kg: 81.5)
    user.weight_trends.create!(trend_date: Date.current, raw_kg: 81.5, ewma_kg: 81.5)
    user.expenditure_estimates.create!(estimate_date: Date.current, estimated_tdee: 2_400, confidence: "low")

    exercise = user.exercises.create!(name: "Zzz Account #{SecureRandom.hex(3)}", modality: "barbell")
    user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current - 7
    )
    template = user.workout_templates.new(name: "Zzz Account Day", weekdays: [ 1 ])
    template.workout_template_exercises.build(exercise: exercise, position: 1)
    template.save!
    session = user.workout_sessions.create!(performed_at: 1.day.ago, workout_template: template)
    session.set_entries.create!(exercise: exercise, set_index: 1, weight_kg: 100, reps: 8, rir: 1)

    food = user.foods.create!(
      name: "Zzz Account Oats", serving_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7
    )
    original = user.food_log_entries.create!(
      food: food, logged_at: 2.days.ago, quantity_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7
    )
    user.food_log_entries.create!(
      food: food, logged_at: 1.day.ago, quantity_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7,
      copied_from_entry: original
    )

    device, = WearableDevice.issue_for!(
      user: user, platform: "ios_healthkit", external_id: "device-#{user.id}", name: "Watch"
    )
    sample = device.wearable_samples.create!(
      user: user, external_id: "workout-#{user.id}", metric_type: "workout",
      started_at: 2.hours.ago, ended_at: 1.hour.ago, value: 2_400, unit: "seconds"
    )
    user.conditioning_sessions.create!(
      wearable_sample: sample, performed_at: 2.hours.ago, activity_type: "run", duration_seconds: 2_400
    )

    parent = account_decision(user, "daily_training")
    child = account_decision(user, "daily_readiness")
    parent.child_links.create!(child_decision: child, role: "readiness")
    user.coach_narratives.create!(
      coaching_decision: parent, question: "Why this plan?", answer: "Because.", status: "complete"
    )
  end

  def account_decision(user, decision_type)
    user.coaching_decisions.create!(
      decision_type: decision_type,
      rule_key: "#{decision_type}.v1",
      rule_version: "1.0.0",
      inputs: {},
      output: { "headline" => "Headline", "guidance" => "Guidance." },
      citations: [],
      confidence: "high"
    )
  end
end
