require "test_helper"

# The cascade on User had twenty `dependent: :destroy` declarations and had
# never run. This builds an account that touches every one of them and then
# erases it, so the ordering and the two lifted guards are exercised rather than
# assumed.
class AccountDeletionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @other = users(:two)
  end

  test "erases an account that has used every part of the app" do
    populate(@user)
    populate(@other)

    assert_difference "User.count", -1 do
      AccountDeletion.new(@user).call
    end

    assert_nil User.find_by(id: @user.id)
  end

  test "leaves every other account untouched" do
    populate(@user)
    populate(@other)
    counts = -> { TRACKED_MODELS.to_h { |model| [ model, model.where(user_id: @other.id).count ] } }
    before = counts.call

    AccountDeletion.new(@user).call

    assert_equal before, counts.call
    assert before.values.all?(&:positive?), "the fixture has to actually populate the other account"
  end

  test "takes every row the account owned with it" do
    populate(@user)

    AccountDeletion.new(@user).call

    TRACKED_MODELS.each do |model|
      assert_equal 0, model.where(user_id: @user.id).count, "#{model} rows outlived the account"
    end
    assert_equal 0, SetEntry.joins(:workout_session).where(workout_sessions: { user_id: @user.id }).count
    assert_equal 0, CoachingDecisionLink.joins(:parent_decision)
      .where(coaching_decisions: { user_id: @user.id }).count
  end

  test "a decision cited by another can still be erased" do
    parent = decision(@user, "daily_training")
    child = decision(@user, "daily_readiness")
    parent.child_links.create!(child_decision: child, role: "readiness")

    # The restrict is what stops evidence disappearing from under a live
    # recommendation; erasure has to lift it rather than be blocked by it. The
    # savepoint keeps the expected violation from poisoning the test transaction.
    assert_raises(ActiveRecord::InvalidForeignKey) do
      ApplicationRecord.transaction(requires_new: true) { child.delete }
    end

    assert_difference "CoachingDecision.count", -2 do
      AccountDeletion.new(@user).call
    end
  end

  test "an exercise with logged sets can still be erased" do
    exercise = @user.exercises.create!(name: "Zzz Erase Squat", modality: "barbell")
    session = @user.workout_sessions.create!(performed_at: 1.day.ago)
    session.set_entries.create!(exercise: exercise, set_index: 1, weight_kg: 100, reps: 5, rir: 2)

    # restrict_with_error stops you losing a lift's history by tidying the
    # catalogue. Erasure is meant to lose it.
    assert_not exercise.destroy
    assert_difference "Exercise.count", -1 do
      AccountDeletion.new(@user).call
    end
  end

  test "catalog exercises are nobody's to delete" do
    ExerciseCatalogImporter.new.call
    populate(@user)
    catalog_count = Exercise.where(user_id: nil).count

    AccountDeletion.new(@user).call

    assert_equal catalog_count, Exercise.where(user_id: nil).count
  end

  # Fails after the guards have been lifted but before the account goes, which is
  # the window where a partial erasure would be possible.
  class ExplodingDeletion < AccountDeletion
    Boom = Class.new(StandardError)

    private

    def release_logged_history
      super
      raise Boom
    end
  end

  test "nothing is half-deleted when the cascade fails" do
    populate(@user)

    # A user row with half its history gone is worse than a failed deletion.
    assert_raises(ExplodingDeletion::Boom) { ExplodingDeletion.new(@user).call }

    assert User.exists?(@user.id)
    assert_predicate @user.workout_sessions.reload, :any?
    assert_predicate CoachingDecisionLink.joins(:parent_decision)
      .where(coaching_decisions: { user_id: @user.id }), :any?
  end

  private

  TRACKED_MODELS = [
    Session, PushSubscription, CoachNarrative, CoachingDecision, ConditioningSession,
    WearableSample, WearableDevice, WorkoutSession, WorkoutTemplate, ExercisePrescription,
    Exercise, FoodLogEntry, Food, GoalPeriod, DailyReadinessInput, ReadinessScore,
    BodyMetric, WeightTrend, ExpenditureEstimate, Mesocycle
  ].freeze

  def populate(user)
    user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    user.push_subscriptions.create!(
      endpoint: "https://web.push.apple.com/#{SecureRandom.hex(4)}", p256dh_key: "k", auth_key: "a"
    )
    user.goal_periods.create!(goal_type: "build_muscle", started_on: Date.current - 30)
    user.mesocycles.create!(focus: "hypertrophy", started_on: Date.current - 7, weeks: 4)
    user.daily_readiness_inputs.create!(metric_date: Date.current, sleep_quality: 4, soreness: 2, fatigue: 2, stress: 2)
    user.readiness_scores.create!(score_date: Date.current, score: 72)
    user.body_metrics.create!(measured_on: Date.current, weight_kg: 81.5)
    user.weight_trends.create!(trend_date: Date.current, raw_kg: 81.5, ewma_kg: 81.5)
    user.expenditure_estimates.create!(estimate_date: Date.current, estimated_tdee: 2_400, confidence: "low")

    exercise = user.exercises.create!(name: "Zzz Erase #{SecureRandom.hex(3)}", modality: "barbell")
    user.exercise_prescriptions.create!(
      exercise: exercise, rep_min: 6, rep_max: 8, target_rir_min: 1, target_rir_max: 2,
      increment_kg: 2.5, working_sets: 3, started_on: Date.current - 7
    )
    template = user.workout_templates.new(name: "Zzz Erase Day", weekdays: [ 1 ])
    template.workout_template_exercises.build(exercise: exercise, position: 1)
    template.save!
    session = user.workout_sessions.create!(performed_at: 1.day.ago, workout_template: template)
    session.set_entries.create!(exercise: exercise, set_index: 1, weight_kg: 100, reps: 8, rir: 1)

    food = user.foods.create!(name: "Zzz Erase Oats", serving_grams: 100, kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7)
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

    parent = decision(user, "daily_training")
    child = decision(user, "daily_readiness")
    parent.child_links.create!(child_decision: child, role: "readiness")
    user.coach_narratives.create!(
      coaching_decision: parent, question: "Why this plan?", answer: "Because.", status: "complete"
    )
  end

  def decision(user, decision_type)
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
