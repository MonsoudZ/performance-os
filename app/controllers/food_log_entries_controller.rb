class FoodLogEntriesController < ApplicationController
  include NutritionWorkspace
  include NutritionRecomputable

  def create
    food = Food.available_to(Current.user).find(food_log_params[:food_id])
    quantity_grams = food_log_params[:quantity_grams].to_d
    macros = food.macros_for(quantity_grams)
    entry = Current.user.food_log_entries.new(
      food: food,
      logged_at: food_log_params[:logged_at],
      meal_type: food_log_params[:meal_type],
      quantity_grams: quantity_grams,
      source: "manual",
      **macros
    )

    if entry.save
      date = Current.user.local_date_at(entry.logged_at)
      recompute_nutrition(date)
      respond_after_mutation(date, notice: "#{food.name} logged.")
    else
      redirect_to nutrition_path, alert: entry.errors.full_messages.to_sentence
    end
  end

  def update
    entry = Current.user.food_log_entries.includes(:food).find(params[:id])
    date = Current.user.local_date_at(entry.logged_at)
    quantity_grams = food_log_params[:quantity_grams].to_d
    macros = entry.macros_for(quantity_grams)

    entry.assign_attributes(
      quantity_grams: quantity_grams,
      meal_type: food_log_params[:meal_type],
      **macros
    )

    if entry.save
      recompute_nutrition(date)
      respond_after_mutation(date, notice: "#{entry.food&.display_name || 'Food entry'} updated.")
    else
      redirect_to nutrition_path, alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    entry = Current.user.food_log_entries.find(params[:id])
    date = Current.user.local_date_at(entry.logged_at)
    entry.destroy!
    recompute_nutrition(date)
    respond_after_mutation(date, notice: "Food entry removed.")
  end

  def copy_yesterday
    date = Current.user.local_date
    result = PreviousDayFoodLogCopier.new(Current.user, destination_date: date).call
    notice = copy_notice(result)

    recompute_nutrition(date) if result.created_entries.any?
    respond_after_mutation(date, notice:)
  end

  private

  def food_log_params
    params.require(:food_log_entry).permit(:food_id, :quantity_grams, :logged_at, :meal_type)
  end

  def respond_after_mutation(date, notice:)
    respond_to do |format|
      format.turbo_stream do
        load_nutrition_workspace(date)
        flash.now[:notice] = notice
        render turbo_stream: turbo_stream.replace(
          "nutrition_log",
          partial: "nutrition/log_workspace"
        )
      end
      format.html { redirect_to nutrition_path, notice: }
    end
  end

  def copy_notice(result)
    if result.source_count.zero?
      "Nothing was logged yesterday."
    elsif result.created_entries.empty?
      "Yesterday’s food is already copied."
    else
      "#{result.created_entries.size} #{'entry'.pluralize(result.created_entries.size)} copied from yesterday."
    end
  end
end
