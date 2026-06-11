require "test_helper"

class WeightTrendMaterializerTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "builds an EWMA chain from daily weight" do
    @user.body_metrics.create!(measured_on: Date.current - 1.day, weight_kg: 80)
    first = WeightTrendMaterializer.new(@user, trend_date: Date.current - 1.day).call
    @user.body_metrics.create!(measured_on: Date.current, weight_kg: 82)
    second = WeightTrendMaterializer.new(@user, trend_date: Date.current).call

    assert_equal 80.0, first.ewma_kg.to_f
    assert_equal 80.5, second.ewma_kg.to_f
  end

  test "recomputes the trend when the day's weight is corrected" do
    @user.body_metrics.create!(measured_on: Date.current - 1.day, weight_kg: 80)
    WeightTrendMaterializer.new(@user, trend_date: Date.current - 1.day).call
    @user.body_metrics.create!(measured_on: Date.current, weight_kg: 82)
    WeightTrendMaterializer.new(@user, trend_date: Date.current).call

    # A second measurement for today changes the daily average (82+90)/2 = 86.
    @user.body_metrics.create!(measured_on: Date.current, weight_kg: 90)
    assert_no_difference "WeightTrend.count" do
      WeightTrendMaterializer.new(@user, trend_date: Date.current).call
    end

    persisted = @user.weight_trends.find_by!(trend_date: Date.current)
    # 0.25 * 86 + 0.75 * 80 = 81.5 (was stale at 80.5 before the fix).
    assert_equal 81.5, persisted.ewma_kg.to_f
  end

  test "forward-propagates the EWMA when an earlier day is backfilled" do
    create_metric(2, 80)
    create_metric(1, 84)
    create_metric(0, 88)
    [ 2, 1, 0 ].each { |offset| WeightTrendMaterializer.new(@user, trend_date: Date.current - offset.days).call }

    # Backfill a correction to the oldest day; downstream rows must update.
    @user.body_metrics.create!(measured_on: Date.current - 2.days, weight_kg: 90)
    WeightTrendMaterializer.new(@user, trend_date: Date.current - 2.days).call

    # day-2: (80+90)/2 = 85 (seed) -> day-1: .25*84+.75*85 = 84.75 -> day0: .25*88+.75*84.75 = 85.5625
    assert_equal 85.0, trend(2).ewma_kg.to_f
    assert_equal 84.75, trend(1).ewma_kg.to_f
    assert_equal 85.56, trend(0).ewma_kg.to_f
  end

  test "drops the trend and re-propagates when a day's measurements are removed" do
    create_metric(2, 80)
    create_metric(1, 84)
    create_metric(0, 88)
    [ 2, 1, 0 ].each { |offset| WeightTrendMaterializer.new(@user, trend_date: Date.current - offset.days).call }

    @user.body_metrics.where(measured_on: Date.current - 1.day).delete_all
    WeightTrendMaterializer.new(@user, trend_date: Date.current - 1.day).call

    assert_nil @user.weight_trends.find_by(trend_date: Date.current - 1.day)
    # day0 now seeds from day-2: .25*88 + .75*80 = 82.0
    assert_equal 82.0, trend(0).ewma_kg.to_f
  end

  private

  def create_metric(offset, weight)
    @user.body_metrics.create!(measured_on: Date.current - offset.days, weight_kg: weight)
  end

  def trend(offset)
    @user.weight_trends.find_by!(trend_date: Date.current - offset.days)
  end
end
