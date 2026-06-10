module NutritionWorkspace
  private

  def load_nutrition_workspace(date)
    @nutrition_date = date
    @foods = Food.available_to(Current.user)
    @food_log_entry = Current.user.food_log_entries.new(logged_at: Time.current, quantity_grams: 100)
    @entries = Current.user.food_log_entries
      .where(logged_at: Current.user.local_day_range(date))
      .includes(:food)
      .order(logged_at: :desc)
    @recent_foods = recent_foods
    @nutrition_decision = Current.user.coaching_decisions
      .where(decision_type: "daily_nutrition")
      .where("inputs ->> 'nutrition_date' = ?", date.iso8601)
      .order(created_at: :desc)
      .first
  end

  def recent_foods
    Current.user.food_log_entries
      .where.not(food_id: nil)
      .includes(:food)
      .order(logged_at: :desc)
      .limit(30)
      .uniq(&:food_id)
      .first(6)
  end
end
