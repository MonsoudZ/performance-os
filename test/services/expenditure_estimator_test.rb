require "test_helper"

class ExpenditureEstimatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    # Every date here is the user's local one, because that is what the estimator
    # reasons in. Mixing in Date.current — the server's — makes the whole file
    # pass or fail depending on the hour it runs at: between 00:00 and 06:00 UTC
    # the two are different days, and the evidence window comes up a day short.
    @today = @user.local_date
  end

  test "waits for enough intake and weight evidence" do
    6.times do |offset|
      date = @today - offset.days
      create_intake(date, 2_500)
      create_trend(date, 80)
    end

    assert_nil ExpenditureEstimator.new(@user).call
  end

  test "estimates expenditure after the evidence threshold" do
    8.times do |offset|
      date = @today - offset.days
      create_intake(date, 2_500)
      create_trend(date, 80)
    end

    estimate = ExpenditureEstimator.new(@user).call

    assert_equal 2_500, estimate.estimated_tdee.to_f
    assert_equal "low", estimate.confidence
    assert_equal "energy_balance", estimate.basis
  end

  test "falls back to the device's own energy while energy balance has nothing to say" do
    3.times { |offset| create_device_energy(@today - (offset + 1).days, active: 620, basal: 1_780) }

    estimate = ExpenditureEstimator.new(@user).call

    assert_equal 2_400, estimate.estimated_tdee.to_f
    assert_equal "wearable_energy", estimate.basis
    assert_equal "low", estimate.confidence, "a device models expenditure, it does not measure it"
    assert_nil estimate.intake_kcal
  end

  test "measured outcome beats the device when both are available" do
    8.times do |offset|
      date = @today - offset.days
      create_intake(date, 2_500)
      create_trend(date, 80)
    end
    create_device_energy(@today - 1.day, active: 620, basal: 1_780)

    estimate = ExpenditureEstimator.new(@user).call

    assert_equal "energy_balance", estimate.basis
    assert_equal 2_500, estimate.estimated_tdee.to_f
  end

  test "ignores the day still being lived" do
    create_device_energy(@today, active: 90, basal: 400)

    # Reading a TDEE off a day at breakfast would set the day's calorie target at
    # a few hundred kilocalories and the plan would tell the user to starve.
    assert_nil ExpenditureEstimator.new(@user).call
  end

  test "ignores a day the device only reported half of" do
    create_device_energy(@today - 1.day, active: 620, basal: nil)

    assert_nil ExpenditureEstimator.new(@user).call
  end

  test "averages the window rather than trusting one day" do
    create_device_energy(@today - 1.day, active: 1_400, basal: 1_800)
    create_device_energy(@today - 2.days, active: 200, basal: 1_800)

    estimate = ExpenditureEstimator.new(@user).call

    # (3,200 + 2,000) / 2. One long hike should not reprice the week.
    assert_equal 2_600, estimate.estimated_tdee.to_f
  end

  test "a later week of real evidence replaces the device estimate for that date" do
    create_device_energy(@today - 1.day, active: 620, basal: 1_780)
    assert_equal "wearable_energy", ExpenditureEstimator.new(@user).call.basis

    8.times do |offset|
      date = @today - offset.days
      create_intake(date, 2_500)
      create_trend(date, 80)
    end

    estimate = ExpenditureEstimator.new(@user).call

    assert_equal "energy_balance", estimate.basis
    assert_equal 1, @user.expenditure_estimates.where(estimate_date: @today).count
  end

  test "ignores intake logged outside the weight-trend span" do
    # Weight trends cover an older 8-day span (stable weight).
    (14..21).each { |offset| create_trend(@today - offset.days, 80) }
    # Intake logged densely within that span...
    (14..21).each { |offset| create_intake(@today - offset.days, 2_000) }
    # ...and a burst of higher intake AFTER the trend span that must not leak in.
    (0..6).each { |offset| create_intake(@today - offset.days, 3_500) }

    estimate = ExpenditureEstimator.new(@user).call

    # Stable weight + 2,000 kcal/day over the trend span => TDEE 2,000.
    # The recent 3,500 kcal days are outside the span and excluded.
    assert_equal 2_000, estimate.estimated_tdee.to_f
  end

  private

  def create_intake(date, kcal)
    @user.food_log_entries.create!(
      logged_at: date.noon,
      quantity_grams: 100,
      kcal: kcal,
      protein_g: 150,
      carb_g: 300,
      fat_g: 70
    )
  end

  # One row per metric per day, the shape the device actually sends: it sums
  # steps and energy locally because raw HealthKit fragments run to hundreds a
  # day.
  def create_device_energy(date, active:, basal:)
    device = @user.wearable_devices.first || WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit", external_id: "device-1", name: "Watch"
    ).first

    { "active_energy_kcal" => active, "basal_energy_kcal" => basal }.each do |metric_type, value|
      next if value.nil?

      device.wearable_samples.create!(
        user: @user,
        external_id: "#{metric_type}:#{date}",
        metric_type: metric_type,
        started_at: @user.local_day_range(date).begin + 6.hours,
        value: value,
        unit: WearableSample::METRIC_UNITS.fetch(metric_type)
      )
    end
  end

  def create_trend(date, weight)
    @user.weight_trends.create!(trend_date: date, raw_kg: weight, ewma_kg: weight)
  end
end
