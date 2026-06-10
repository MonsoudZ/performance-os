class NutritionController < ApplicationController
  include NutritionWorkspace

  def show
    today = Current.user.local_date
    load_nutrition_workspace(today)
    @food = Current.user.foods.new(
      serving_grams: 100,
      protein_g: 0,
      carb_g: 0,
      fat_g: 0,
      kcal: 0
    )
    @body_metric = Current.user.body_metrics.new(measured_on: today)
    @weight_trends = Current.user.weight_trends.order(trend_date: :desc).limit(7)
    @expenditure = Current.user.expenditure_estimates.order(estimate_date: :desc).first
  end
end
