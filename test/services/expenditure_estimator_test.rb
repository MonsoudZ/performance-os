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
