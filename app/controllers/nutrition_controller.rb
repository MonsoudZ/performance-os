class NutritionController < ApplicationController
  def show
    today = Current.user.local_date
    @foods = Food.available_to(Current.user)
    @food = Current.user.foods.new(
      serving_grams: 100,
      protein_g: 0,
      carb_g: 0,
      fat_g: 0,
      kcal: 0
    )
    @food_log_entry = Current.user.food_log_entries.new(logged_at: Time.current, quantity_grams: 100)
    @body_metric = Current.user.body_metrics.new(measured_on: today)
    @entries = Current.user.food_log_entries
      .where(logged_at: Current.user.local_day_range(today))
      .includes(:food)
      .order(logged_at: :desc)
    @nutrition_decision = Current.user.coaching_decisions
      .where(decision_type: "daily_nutrition")
      .where("inputs ->> 'nutrition_date' = ?", today.iso8601)
      .order(created_at: :desc)
      .first
    @weight_trends = Current.user.weight_trends.order(trend_date: :desc).limit(7)
    @expenditure = Current.user.expenditure_estimates.order(estimate_date: :desc).first
  end
end
