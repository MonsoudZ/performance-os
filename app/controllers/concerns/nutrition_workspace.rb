module NutritionWorkspace
  private

  def load_nutrition_workspace(date)
    @nutrition_date = date
    @foods = Food.available_to(Current.user)
    @food_log_entry = Current.user.food_log_entries.new(
      logged_at: Time.current,
      meal_type: FoodLogEntry.meal_type_for(Time.current),
      quantity_grams: 100
    )
    @entries = Current.user.food_log_entries
      .where(logged_at: Current.user.local_day_range(date))
      .includes(:food)
      .order(logged_at: :desc)
    @entries_by_meal = FoodLogEntry::MEAL_TYPES.index_with do |meal_type|
      @entries.select { |entry| entry.meal_type == meal_type }
    end
    @yesterday_entry_count = Current.user.food_log_entries
      .where(logged_at: Current.user.local_day_range(date.yesterday))
      .count
    @recent_foods = recent_foods
    @nutrition_decision = Current.user.coaching_decisions
      .of_type("daily_nutrition")
      .for_input("nutrition_date", date.iso8601)
      .latest_first
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
