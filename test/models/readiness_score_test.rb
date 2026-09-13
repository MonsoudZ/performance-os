require "test_helper"

# The score a day's check-in produces. ReadinessEvaluator replaces it wholesale
# rather than editing it, because it is derived state: every component is
# recomputed from the check-in, so there is nothing to preserve.
class ReadinessScoreTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a score outside 0-100 is rejected by the model and by the database" do
    assert_not @user.readiness_scores.new(score_date: Date.current, score: 101).valid?
    assert_not @user.readiness_scores.new(score_date: Date.current, score: -1).valid?

    out_of_range = @user.readiness_scores.new(score_date: Date.current, score: 140)
    assert_raises(ActiveRecord::StatementInvalid) { out_of_range.save(validate: false) }
  end

  test "one score per user per day, enforced by the index and not only the validation" do
    @user.readiness_scores.create!(score_date: Date.current, score: 70)
    duplicate = @user.readiness_scores.new(score_date: Date.current, score: 80)

    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "two users can hold a score for the same day" do
    @user.readiness_scores.create!(score_date: Date.current, score: 70)

    assert_difference "ReadinessScore.count", 1 do
      users(:two).readiness_scores.create!(score_date: Date.current, score: 55)
    end
  end

  test "re-scoring a day replaces the row rather than editing it" do
    @user.readiness_scores.create!(score_date: Date.current, score: 70, components: { "sleep" => 3 })

    # The pattern ReadinessEvaluator uses: every component is recomputed from the
    # check-in, so there is nothing in the old row worth carrying forward.
    @user.readiness_scores.where(score_date: Date.current).delete_all
    @user.readiness_scores.create!(score_date: Date.current, score: 88, components: { "sleep" => 5 })

    score = @user.readiness_scores.where(score_date: Date.current).sole
    assert_equal 88, score.score
    assert_equal({ "sleep" => 5 }, score.components)
  end
end
