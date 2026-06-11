class FoodsController < ApplicationController
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
end
