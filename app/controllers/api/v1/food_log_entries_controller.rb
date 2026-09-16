module Api
  module V1
    # Logging, correcting and removing what was eaten.
    #
    # The macros are computed here from the food rather than accepted from the
    # client, for the same reason the web does it: a logged entry is a record of
    # what was eaten, and letting the caller supply both the portion and the
    # numbers that are supposed to follow from it would let the two disagree.
    #
    # Every write recomputes the day it lands on — the entry's own local day, not
    # today, so a backdated log updates the day it belongs to.
    class FoodLogEntriesController < BaseController
      include NutritionRecomputable

      def create
        food = Food.available_to(current_user).find(food_log_params[:food_id])
        quantity_grams = food_log_params[:quantity_grams].to_d
        entry = current_user.food_log_entries.new(
          food: food,
          logged_at: logged_at,
          # Explicitly nil when the client did not say, so the model infers the
          # meal from the timestamp. Leaving the key out entirely would take the
          # column default instead and file a 9pm snack under "snack" by luck
          # rather than by the rule.
          meal_type: food_log_params[:meal_type].presence,
          quantity_grams: quantity_grams,
          source: "manual",
          **food.macros_for(quantity_grams)
        )

        if entry.save
          recompute_nutrition(current_user.local_date_at(entry.logged_at))
          render json: { data: FoodLogEntrySerializer.new(entry).as_json }, status: :created
        else
          invalid(entry)
        end
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      def update
        entry = current_user.food_log_entries.includes(:food).find(params[:id])
        day = current_user.local_date_at(entry.logged_at)

        if food_log_params[:quantity_grams].present?
          quantity_grams = food_log_params[:quantity_grams].to_d
          entry.assign_attributes(quantity_grams: quantity_grams, **entry.macros_for(quantity_grams))
        end
        entry.meal_type = food_log_params[:meal_type] if food_log_params[:meal_type].present?

        if entry.save
          recompute_nutrition(day)
          render json: { data: FoodLogEntrySerializer.new(entry).as_json }
        else
          invalid(entry)
        end
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      def destroy
        entry = current_user.food_log_entries.find(params[:id])
        day = current_user.local_date_at(entry.logged_at)
        entry.destroy!
        recompute_nutrition(day)

        head :no_content
      rescue ActiveRecord::RecordNotFound
        not_found
      end

      # Yesterday again, for the days that are. The copier is what decides what
      # "again" means; it is idempotent, so tapping twice copies once.
      def copy_yesterday
        day = current_user.local_date
        result = PreviousDayFoodLogCopier.new(current_user, destination_date: day).call
        recompute_nutrition(day) if result.created_entries.any?

        render json: {
          data: result.created_entries.map { |entry| FoodLogEntrySerializer.new(entry).as_json },
          meta: { source_count: result.source_count }
        }
      end

      private

      def food_log_params
        params.require(:food_log_entry).permit(:food_id, :quantity_grams, :logged_at, :meal_type)
      end

      def logged_at
        food_log_params[:logged_at].presence || Time.current
      end

      def invalid(entry)
        render json: { error: "Invalid food log entry", details: entry.errors.full_messages },
          status: :unprocessable_entity
      end
    end
  end
end
