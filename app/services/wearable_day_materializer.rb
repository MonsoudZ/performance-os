# Everything one synced day turns into, in the order the results depend on each
# other: a weigh-in feeds the weight trend, which feeds expenditure, which feeds
# the calorie target the plan is built against.
#
# Steps and energy are not materialized into anything — they are read straight
# from the samples by ExpenditureEstimator and the nutrition page, because unlike
# a workout or a weigh-in they are not events the user could also have logged by
# hand.
class WearableDayMaterializer
  def initialize(user, metric_date:)
    @user = user
    @metric_date = metric_date
  end

  def call
    if WearableBodyMassMaterializer.new(user, metric_date: metric_date).call
      WeightTrendMaterializer.new(user, trend_date: metric_date).call
    end

    WearableWorkoutMaterializer.new(user, metric_date: metric_date).call
    WearableReadinessMaterializer.new(user, metric_date: metric_date).call
  end

  private

  attr_reader :user, :metric_date
end
