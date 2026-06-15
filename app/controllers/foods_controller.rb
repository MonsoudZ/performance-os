class FoodsController < ApplicationController
  include NutritionRecomputable

  before_action :set_food, only: %i[edit update destroy]

  def create
    food = Current.user.foods.new(food_params)

    if food.save
      redirect_to nutrition_path, notice: "Food added to your catalog."
    else
      redirect_to nutrition_path, alert: food.errors.full_messages.to_sentence
    end
  end

  def search
    @query = params[:q].to_s.strip
    @results = @query.present? ? FoodDatabaseSearch.new(@query).call : []
  end

  def import
    food = Current.user.foods.new(import_params.merge(source: "import"))

    if food.save
      redirect_to nutrition_path, notice: "#{food.display_name} added from the food database."
    else
      redirect_to search_foods_path(q: params[:q]), alert: food.errors.full_messages.to_sentence
    end
  end

  # One-step: import the food (deduped) and log a serving in a single tap.
  def log
    food = find_or_import_food
    quantity = 100.to_d
    entry = Current.user.food_log_entries.new(
      food: food,
      logged_at: Time.current,
      meal_type: FoodLogEntry.meal_type_for(Time.current),
      quantity_grams: quantity,
      source: "manual",
      **food.macros_for(quantity)
    )

    if entry.save
      recompute_nutrition
      redirect_to nutrition_path, notice: "#{food.display_name} logged (100 g — adjust below if needed)."
    else
      redirect_to search_foods_path(q: params[:q]), alert: entry.errors.full_messages.to_sentence
    end
  end

  def edit
  end

  def update
    if @food.update(food_params)
      # Logged entries snapshot their macros, so editing only affects future logs.
      redirect_to nutrition_path, notice: "#{@food.display_name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @food.destroy!
    redirect_to nutrition_path, notice: "#{@food.display_name} removed from your catalog."
  end

  private

  # Scoped to the user's own catalog rows; the shared catalog (user_id IS NULL)
  # is not editable.
  def set_food
    @food = Current.user.foods.find(params[:id])
  end

  def food_params
    params.require(:food).permit(
      :name,
      :brand,
      :serving_grams,
      :kcal,
      :protein_g,
      :carb_g,
      :fat_g
    )
  end

  alias import_params food_params

  def find_or_import_food
    attributes = import_params
    Current.user.foods
      .create_with(attributes.merge(source: "import"))
      .find_or_create_by!(name: attributes[:name], brand: attributes[:brand].presence)
  end
end
