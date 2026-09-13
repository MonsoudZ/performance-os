require "test_helper"

# The EWMA of a user's weigh-ins, one row per day. WeightTrendMaterializer owns
# every write; the (user_id, trend_date) unique index is what makes "one per day"
# true rather than merely intended.
class WeightTrendTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a trend weight has to be a real weight" do
    assert_not @user.weight_trends.new(trend_date: Date.current, ewma_kg: 0).valid?
    assert_not @user.weight_trends.new(trend_date: Date.current, ewma_kg: -1).valid?
    assert_predicate @user.weight_trends.new(trend_date: Date.current, ewma_kg: 81.5), :valid?
  end

  test "a raw weigh-in is optional so a day can carry only a smoothed value" do
    # The EWMA chain continues across days with no weigh-in of their own.
    trend = @user.weight_trends.create!(trend_date: Date.current, ewma_kg: 81.5)

    assert_nil trend.raw_kg
  end

  test "one trend per user per day, enforced by the index and not only the validation" do
    @user.weight_trends.create!(trend_date: Date.current, ewma_kg: 81.5)
    duplicate = @user.weight_trends.new(trend_date: Date.current, ewma_kg: 82)

    assert_not duplicate.valid?
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "a trend is stored at the same scale as every other weight in the app" do
    @user.weight_trends.create!(trend_date: Date.current, raw_kg: "81.646627", ewma_kg: "81.646627")

    # Anything coarser and a pound read back off the trend strip would not be the
    # pound that went in, which is why Units::WEIGHT_SCALE is 6.
    assert_equal BigDecimal("81.646627"), @user.weight_trends.sole.ewma_kg
  end

  test "a stored trend can be corrected in place" do
    @user.weight_trends.create!(trend_date: Date.current, raw_kg: 80, ewma_kg: 80)
    trend = @user.weight_trends.sole

    trend.update!(ewma_kg: 81)

    assert_equal BigDecimal("81"), @user.weight_trends.sole.ewma_kg
  end
end
