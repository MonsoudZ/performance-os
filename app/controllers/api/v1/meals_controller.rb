module Api
  module V1
    # Building a meal, editing one, and logging it in a single tap.
    #
    # The foods and portions arrive as nested attributes, the same shape the web
    # editor posts, so there is one set of rules about what a meal is rather than
    # two. That shape has a contract worth knowing: an item carrying an `id` is
    # updated, one without is added, and one carrying `_destroy` is removed.
    # **An item simply left out is kept.** A client sending a shorter list is
    # editing the items it named, not declaring the meal's new contents — making
    # omission mean deletion would turn a partial payload into data loss.
    class MealsController < BaseController
      include NutritionRecomputable

      before_action :set_requested_date, only: :create_from_log

      def index
        meals = current_user.meals.includes(meal_items: :food).order(:name)

        render json: { data: meals.map { |meal| MealSerializer.new(meal).as_json } }
      end

      def show
        render json: { data: MealSerializer.new(find_meal).as_json }
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      def create
        meal = current_user.meals.new(meal_params)
        meal.renumber_items

        if meal.save
          render json: { data: MealSerializer.new(meal).as_json }, status: :created
        else
          invalid(meal)
        end
      end

      def update
        meal = find_meal
        meal.assign_attributes(meal_params)
        meal.renumber_items

        if meal.save
          render json: { data: MealSerializer.new(meal.reload).as_json }
        else
          invalid(meal)
        end
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      # Deleting a meal leaves the entries it has already logged alone: those are
      # a record of what was eaten, not a copy of the meal.
      def destroy
        find_meal.destroy!

        head :no_content
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      # Every food in the meal, logged at once, filed under the meal happening
      # now rather than the one it was last eaten at.
      def log
        result = MealLogger.new(find_meal).call
        recompute_nutrition

        render json: {
          data: result.entries.map { |entry| FoodLogEntrySerializer.new(entry).as_json }
        }, status: :created
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      # Keep a meal already eaten, the way a logged session becomes a workout.
      # What you ate and how much is already recorded, so this costs a name
      # rather than re-entering every food — and the name is optional, because
      # the service suggests one and steps around a name already taken.
      def create_from_log
        meal = MealFromLoggedEntries.new(current_user, logged_entries, name: params[:name]).call

        if meal.persisted?
          render json: { data: MealSerializer.new(meal).as_json }, status: :created
        else
          invalid(meal)
        end
      end

      private

      def find_meal
        current_user.meals.includes(meal_items: :food).find(params[:id])
      end

      def meal_params
        params.require(:meal).permit(
          :name,
          meal_items_attributes: %i[id food_id quantity_grams position _destroy]
        )
      end

      # The day is the user's own, so "yesterday's dinner" means the day they
      # lived rather than UTC's. A meal type narrows it to one sitting; without
      # one the whole day is the meal, which is what somebody saving a day of
      # eating as a template means.
      def logged_entries
        scope = current_user.food_log_entries.where(logged_at: current_user.local_day_range(date))
        scope = scope.where(meal_type: params[:meal_type]) if params[:meal_type].present?
        scope.includes(:food).order(:logged_at).to_a
      end

      def invalid(meal)
        render json: { error: "Invalid meal", details: meal.errors.full_messages },
          status: :unprocessable_entity
      end
    end
  end
end
