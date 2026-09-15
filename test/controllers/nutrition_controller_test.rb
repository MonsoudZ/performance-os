require "test_helper"

class NutritionControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(time_zone: "America/Denver")
    sign_in_as(@user)
    @device, = WearableDevice.issue_for!(
      user: @user, platform: "ios_healthkit", external_id: "device-1", name: "Watch"
    )
  end

  # Tapping a recent food files it under the meal happening now. It used to
  # carry over the meal it was last eaten at, so an entry stamped 8pm landed in
  # the breakfast group — the record contradicting its own timestamp.
  test "a one-tap food is filed under the meal happening now" do
    oats = @user.foods.create!(name: "Zzz Oats", kcal: 380, protein_g: 13, carb_g: 67, fat_g: 7, serving_grams: 100)
    @user.food_log_entries.create!(
      food: oats, logged_at: Time.current.in_time_zone(@user.time_zone).change(hour: 7),
      meal_type: "breakfast", quantity_grams: 80, source: "manual", **oats.macros_for(80)
    )

    travel_to Time.current.in_time_zone(@user.time_zone).change(hour: 20) do
      get nutrition_path

      assert_response :success
      assert_select ".recent-foods form input[name=?][value=?]", "food_log_entry[meal_type]", "dinner"
      assert_select ".recent-foods form input[name=?][value=?]", "food_log_entry[meal_type]", "breakfast", count: 0
      # The portion is what was remembered, and it is still offered.
      assert_select ".recent-foods form input[name=?][value=?]", "food_log_entry[quantity_grams]", "80.0"
    end
  end

  test "says where an expenditure estimate came from" do
    @user.expenditure_estimates.create!(
      estimate_date: @user.local_date, estimated_tdee: 2_400, confidence: "low", basis: "wearable_energy"
    )

    get nutrition_path

    assert_response :success
    # Two methods produce this number and they are worth very different amounts.
    assert_select ".evidence-note", text: /resting and active energy/
  end

  test "shows the day's steps and energy when a device reported them" do
    create_total("step_count", 11_500)
    create_total("active_energy_kcal", 620)
    create_total("basal_energy_kcal", 1_780)

    get nutrition_path

    assert_response :success
    assert_select ".evidence-note", text: /11,500.*steps/m
    assert_select ".evidence-note", text: /2,400 kcal/
  end

  test "says nothing about activity when no device has reported any" do
    get nutrition_path

    assert_response :success
    assert_select ".evidence-note", { text: /Your watch reported/, count: 0 }
  end

  test "marks a synced weigh-in apart from one logged by hand" do
    @user.body_metrics.create!(measured_on: @user.local_date, weight_kg: 81.5, source: "healthkit")
    @user.body_metrics.create!(measured_on: @user.local_date - 1, weight_kg: 81.9, source: "manual")

    get nutrition_path

    assert_response :success
    assert_select ".compact-list__item strong .pill", 1
  end

  test "renders the weight trend in the reader's units" do
    @user.update!(unit_system: "imperial")
    @user.weight_trends.create!(trend_date: @user.local_date, raw_kg: 85.05, ewma_kg: 85.05)

    get nutrition_path

    assert_response :success
    # The strip is labelled in pounds by the form above it, so printing the
    # stored kilograms here read as a 4 kg overnight loss.
    assert_select ".trend-strip strong", text: "187.5"
  end

  private

  def create_total(metric_type, value)
    @device.wearable_samples.create!(
      user: @user,
      external_id: "#{metric_type}:#{@user.local_date}",
      metric_type: metric_type,
      started_at: @user.local_day_range(@user.local_date).begin + 6.hours,
      value: value,
      unit: WearableSample::METRIC_UNITS.fetch(metric_type)
    )
  end
end
