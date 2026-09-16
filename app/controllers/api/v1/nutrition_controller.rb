module Api
  module V1
    # The day's eating, in one request.
    #
    # Everything the nutrition page shows: what has been logged, what the engine
    # concluded, and the two shortcuts that make logging one tap — the foods this
    # user eats most and the meals they have saved.
    class NutritionController < BaseController
      before_action :set_requested_date

      def show
        render json: {
          data: NutritionDaySerializer.new(
            current_user,
            date: date,
            entries: entries,
            decision: decision,
            frequent_foods: FrequentFoods.new(current_user).call,
            meals: current_user.meals.includes(meal_items: :food).order(:name),
            yesterday_entry_count: yesterday_entry_count
          ).as_json
        }
      end

      private

      def entries
        current_user.food_log_entries
          .where(logged_at: current_user.local_day_range(date))
          .includes(:food)
          .order(logged_at: :desc)
      end

      # Scoped to active_evidence like every other lookup that feeds a
      # conclusion: a withdrawn decision is part of the record but is never the
      # answer to "what does the engine say today".
      def decision
        current_user.coaching_decisions
          .active_evidence
          .of_type("daily_nutrition")
          .for_input("nutrition_date", date.iso8601)
          .latest_first
          .first
      end

      def yesterday_entry_count
        current_user.food_log_entries
          .where(logged_at: current_user.local_day_range(date.yesterday))
          .count
      end
    end
  end
end
