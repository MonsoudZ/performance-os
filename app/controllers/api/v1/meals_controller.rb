module Api
  module V1
    # Saved meals, and logging one in a single tap.
    #
    # Building and editing a meal is still the web's job — it is a form with a
    # row per food, done once, and the phone's job is the tap afterwards.
    class MealsController < BaseController
      include NutritionRecomputable

      def index
        meals = current_user.meals.includes(meal_items: :food).order(:name)

        render json: { data: meals.map { |meal| MealSerializer.new(meal).as_json } }
      end

      # Every food in the meal, logged at once, filed under the meal happening
      # now rather than the one it was last eaten at.
      def log
        meal = current_user.meals.includes(meal_items: :food).find(params[:id])
        result = MealLogger.new(meal).call
        recompute_nutrition

        render json: {
          data: result.entries.map { |entry| FoodLogEntrySerializer.new(entry).as_json }
        }, status: :created
      rescue ActiveRecord::RecordNotFound
        not_found
      end
    end
  end
end
