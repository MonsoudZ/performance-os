require "test_helper"

class WeightTrendMaterializerTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "creates an immutable EWMA snapshot from daily weight" do
    @user.body_metrics.create!(measured_on: Date.current - 1.day, weight_kg: 80)
    first = WeightTrendMaterializer.new(@user, trend_date: Date.current - 1.day).call
    @user.body_metrics.create!(measured_on: Date.current, weight_kg: 82)
    second = WeightTrendMaterializer.new(@user, trend_date: Date.current).call

    assert_equal 80.0, first.ewma_kg.to_f
    assert_equal 80.5, second.ewma_kg.to_f

    @user.body_metrics.create!(measured_on: Date.current, weight_kg: 90)
    assert_no_difference "WeightTrend.count" do
      WeightTrendMaterializer.new(@user, trend_date: Date.current).call
    end
    persisted = @user.weight_trends.find_by!(trend_date: Date.current)
    assert_equal 80.5, persisted.ewma_kg.to_f
  end
end
