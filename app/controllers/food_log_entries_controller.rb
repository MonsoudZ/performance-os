class FoodLogEntriesController < ApplicationController
  def create
    food = Food.available_to(Current.user).find(food_log_params[:food_id])
    quantity_grams = food_log_params[:quantity_grams].to_d
    macros = food.macros_for(quantity_grams)
    entry = Current.user.food_log_entries.new(
      food: food,
      logged_at: food_log_params[:logged_at],
      quantity_grams: quantity_grams,
      source: "manual",
      **macros
    )

    if entry.save
      refresh_nutrition(Current.user.local_date_at(entry.logged_at))
      redirect_to nutrition_path, notice: "#{food.name} logged."
    else
      redirect_to nutrition_path, alert: entry.errors.full_messages.to_sentence
    end
  end

  private

  def food_log_params
    params.require(:food_log_entry).permit(:food_id, :quantity_grams, :logged_at)
  end

  def refresh_nutrition(date)
    ExpenditureEstimator.new(Current.user, estimate_date: date).call
    NutritionEvaluator.new(Current.user, nutrition_date: date).call
    DailyTrainingOrchestrator.new(Current.user, plan_date: date).call if date == Current.user.local_date
  end
end
