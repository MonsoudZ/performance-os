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
end
