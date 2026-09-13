require "test_helper"

# Four tables in this schema carry no primary key. They hold derived, naturally
# keyed state — one row per user per day, one row per exercise/muscle pair — and
# `id: false` says so.
#
# The cost is a trap Active Record gives no warning about: it builds every
# UPDATE and DELETE for a loaded record around the primary key, so with none it
# emits `WHERE "" IS NULL` and Postgres rejects the statement outright. save!,
# update!, destroy and `dependent: :destroy` all go that way. Rows must be
# reached through their unique index with update_all/delete_all instead.
#
# This has been a live bug twice — ExpenditureEstimator wrote a second estimate
# for a date through save!, and re-importing a catalog exercise whose muscles
# changed went through update! — so the point of this test is to catch the third
# one at the moment a fifth keyless table appears.
class KeylessTablesTest < ActiveSupport::TestCase
  KEYLESS_MODELS = %w[
    ExerciseMuscleContribution
    ExpenditureEstimate
    ReadinessScore
    WeightTrend
  ].freeze

  test "the set of primary-keyless models is the set this codebase knows about" do
    Rails.application.eager_load!
    discovered = ApplicationRecord.descendants
      .select { |model| model.table_exists? && model.primary_key.nil? }
      .map(&:name)
      .sort

    assert_equal KEYLESS_MODELS, discovered,
      "a new keyless table cannot be written through save! — read this test before adding one"
  end

  test "every keyless table has a unique index to reach its rows by instead" do
    KEYLESS_MODELS.each do |name|
      model = name.constantize
      indexes = ActiveRecord::Base.connection.indexes(model.table_name)

      assert indexes.any?(&:unique),
        "#{name} has no unique index, so there is no natural key to write through"
    end
  end

  test "writing a loaded keyless row through save! fails loudly rather than silently" do
    user = users(:one)
    user.readiness_scores.create!(score_date: Date.current, score: 70)
    score = user.readiness_scores.order(:score_date).last

    score.score = 80

    # Loud is the good case. The danger was never that this corrupts data — it
    # is that the failure only appears on the *second* write for a given key, so
    # it ships looking fine.
    assert_raises(ActiveRecord::StatementInvalid) { score.save! }
  end

  test "reaching the same row through its unique index works" do
    user = users(:one)
    user.readiness_scores.create!(score_date: Date.current, score: 70)

    user.readiness_scores.where(score_date: Date.current).update_all(score: 80)

    assert_equal 80, user.readiness_scores.order(:score_date).last.score
  end
end
