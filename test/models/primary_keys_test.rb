require "test_helper"

# Four tables in this schema used to carry no primary key — readiness_scores,
# weight_trends, expenditure_estimates and exercise_muscle_contributions. Each
# row is derived state addressed by a natural key, so an id looked like dead
# weight.
#
# It cost more than it saved. Active Record builds every UPDATE and DELETE for a
# loaded record around the primary key, so with none it emits `WHERE "" IS NULL`
# and Postgres rejects the statement outright: save!, update!, destroy and
# `dependent: :destroy` all fail that way, and only on the *second* write for a
# given key, so the failure ships looking fine. It was four live bugs before it
# was found.
#
# They all have ids now. This is the guard against the fifth one.
class PrimaryKeysTest < ActiveSupport::TestCase
  test "every model has a primary key to be written through" do
    Rails.application.eager_load!
    keyless = ApplicationRecord.descendants
      .select { |model| model.table_exists? && model.primary_key.nil? }
      .map(&:name)
      .sort

    assert_empty keyless,
      "a table with no primary key cannot be updated or destroyed through the ORM at all — " \
      "give it an id, and keep the unique index that carries its natural key"
  end

  test "the natural keys the ids replaced are still what enforce uniqueness" do
    {
      "ReadinessScore" => %w[user_id score_date],
      "WeightTrend" => %w[user_id trend_date],
      "ExpenditureEstimate" => %w[user_id estimate_date],
      "ExerciseMuscleContribution" => %w[exercise_id muscle_group_id]
    }.each do |name, columns|
      model = name.constantize
      indexes = ActiveRecord::Base.connection.indexes(model.table_name)

      assert indexes.any? { |index| index.unique && index.columns == columns },
        "#{name} lost the unique index on #{columns.join(', ')} — the id does not enforce it"
    end
  end

  test "a derived row can be loaded, changed and written back" do
    user = users(:one)
    user.readiness_scores.create!(score_date: Date.current, score: 70)
    score = user.readiness_scores.sole

    score.update!(score: 80)

    assert_equal 80, score.reload.score
  end

  test "a derived row can be destroyed one at a time" do
    user = users(:one)
    user.weight_trends.create!(trend_date: Date.current, raw_kg: 80, ewma_kg: 80)

    assert_difference "WeightTrend.count", -1 do
      user.weight_trends.sole.destroy!
    end
  end
end
