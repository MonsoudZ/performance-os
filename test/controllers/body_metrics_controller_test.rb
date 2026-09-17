require "test_helper"

class BodyMetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "logs a weigh-in and enqueues a recompute" do
    assert_difference "BodyMetric.count", 1 do
      assert_enqueued_with(job: BodyMetricRecomputeJob) do
        post body_metrics_path, params: { body_metric: { weight_kg: 80, measured_on: Date.current } }
      end
    end

    assert_redirected_to nutrition_path
  end

  test "removes a weigh-in and recomputes" do
    metric = @user.body_metrics.create!(weight_kg: 80, measured_on: Date.current)

    assert_difference "BodyMetric.count", -1 do
      assert_enqueued_with(job: BodyMetricRecomputeJob) do
        delete body_metric_path(metric)
      end
    end

    assert_redirected_to nutrition_path
  end

  test "deleting the last weigh-in for a day drops its weight trend" do
    @user.body_metrics.create!(weight_kg: 80, measured_on: Date.current - 1.day)
    metric = @user.body_metrics.create!(weight_kg: 82, measured_on: Date.current)
    WeightTrendMaterializer.new(@user, trend_date: Date.current - 1.day).call
    WeightTrendMaterializer.new(@user, trend_date: Date.current).call
    assert @user.weight_trends.exists?(trend_date: Date.current)

    perform_enqueued_jobs { delete body_metric_path(metric) }

    assert_not @user.weight_trends.exists?(trend_date: Date.current)
  end

  test "cannot delete another user's weigh-in" do
    foreign = users(:two).body_metrics.create!(weight_kg: 90, measured_on: Date.current)

    delete body_metric_path(foreign)

    assert_response :not_found
    assert BodyMetric.exists?(foreign.id)
  end
  # The column, its validation and its check constraint all existed with nothing
  # writing to them. A percentage is the same number in both unit systems, so it
  # is the one figure on this form the converter must leave alone.
  test "body fat is recorded alongside the weight, unconverted" do
    sign_in_as(users(:two)) # imperial, so a converted figure would show

    post body_metrics_path, params: {
      body_metric: { measured_on: Date.current, weight_kg: 200, body_fat_pct: 18.4 }
    }

    metric = BodyMetric.order(:id).last
    assert_equal BigDecimal("18.4"), metric.body_fat_pct
    # The weight beside it still converts, which is what makes this a real test.
    assert_in_delta 90.72, metric.weight_kg.to_f, 0.01
  end

  test "a weigh-in with no body fat is still a weigh-in" do
    post body_metrics_path, params: { body_metric: { measured_on: Date.current, weight_kg: 82.4 } }

    assert_nil BodyMetric.order(:id).last.body_fat_pct
  end

  test "an impossible body fat percentage is refused" do
    assert_no_difference "BodyMetric.count" do
      post body_metrics_path, params: {
        body_metric: { measured_on: Date.current, weight_kg: 82.4, body_fat_pct: 140 }
      }
    end
  end
end
