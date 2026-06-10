require "test_helper"

class ExpenditureEstimatorTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "waits for enough intake and weight evidence" do
    6.times do |offset|
      date = Date.current - offset.days
      create_intake(date, 2_500)
      create_trend(date, 80)
    end

    assert_nil ExpenditureEstimator.new(@user).call
  end

  test "estimates expenditure after the evidence threshold" do
    8.times do |offset|
      date = Date.current - offset.days
      create_intake(date, 2_500)
      create_trend(date, 80)
    end

    estimate = ExpenditureEstimator.new(@user).call

    assert_equal 2_500, estimate.estimated_tdee.to_f
    assert_equal "low", estimate.confidence
  end

  test "ignores intake logged outside the weight-trend span" do
    # Weight trends cover an older 8-day span (stable weight).
    (14..21).each { |offset| create_trend(Date.current - offset.days, 80) }
    # Intake logged densely within that span...
    (14..21).each { |offset| create_intake(Date.current - offset.days, 2_000) }
    # ...and a burst of higher intake AFTER the trend span that must not leak in.
    (0..6).each { |offset| create_intake(Date.current - offset.days, 3_500) }

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

  def create_trend(date, weight)
    @user.weight_trends.create!(trend_date: date, raw_kg: weight, ewma_kg: weight)
  end
end
