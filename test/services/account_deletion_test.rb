require "test_helper"

# The cascade on User had twenty `dependent: :destroy` declarations and had
# never run. This builds an account that touches every one of them and then
# erases it, so the ordering and the two lifted guards are exercised rather than
# assumed.
class AccountDeletionTest < ActiveSupport::TestCase
  include AccountFixture

  setup do
    @user = users(:one)
    @other = users(:two)
  end

  test "erases an account that has used every part of the app" do
    populate_account(@user)
    populate_account(@other)

    assert_difference "User.count", -1 do
      AccountDeletion.new(@user).call
    end

    assert_nil User.find_by(id: @user.id)
  end

  test "leaves every other account untouched" do
    populate_account(@user)
    populate_account(@other)
    counts = -> { AccountFixture::ACCOUNT_MODELS.to_h { |model| [ model, model.where(user_id: @other.id).count ] } }
    before = counts.call

    AccountDeletion.new(@user).call

    assert_equal before, counts.call
    assert before.values.all?(&:positive?), "the fixture has to actually populate the other account"
  end

  test "takes every row the account owned with it" do
    populate_account(@user)

    AccountDeletion.new(@user).call

    AccountFixture::ACCOUNT_MODELS.each do |model|
      assert_equal 0, model.where(user_id: @user.id).count, "#{model} rows outlived the account"
    end
    assert_equal 0, SetEntry.joins(:workout_session).where(workout_sessions: { user_id: @user.id }).count
    assert_equal 0, CoachingDecisionLink.joins(:parent_decision)
      .where(coaching_decisions: { user_id: @user.id }).count
  end

  test "a decision cited by another can still be erased" do
    parent = account_decision(@user, "daily_training")
    child = account_decision(@user, "daily_readiness")
    parent.child_links.create!(child_decision: child, role: "readiness")

    # The restrict is what stops evidence disappearing from under a live
    # recommendation; erasure has to lift it rather than be blocked by it. The
    # savepoint keeps the expected violation from poisoning the test transaction.
    #
    # StatementInvalid rather than its InvalidForeignKey subclass: Postgres 16
    # reports this as a foreign-key violation and 18 as a restrict violation,
    # which Rails wraps differently, and the point here is the guard, not the
    # server's choice of SQLSTATE.
    error = assert_raises(ActiveRecord::StatementInvalid) do
      ApplicationRecord.transaction(requires_new: true) { child.delete }
    end
    assert_match(/violates|restrict/i, error.message)

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
    populate_account(@user)
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
    populate_account(@user)

    # A user row with half its history gone is worse than a failed deletion.
    assert_raises(ExplodingDeletion::Boom) { ExplodingDeletion.new(@user).call }

    assert User.exists?(@user.id)
    assert_predicate @user.workout_sessions.reload, :any?
    assert_predicate CoachingDecisionLink.joins(:parent_decision)
      .where(coaching_decisions: { user_id: @user.id }), :any?
  end
end
