class FoodsController < ApplicationController
  def create
    food = Current.user.foods.new(food_params)

    if food.save
      redirect_to nutrition_path, notice: "Food added to your catalog."
    else
      redirect_to nutrition_path, alert: food.errors.full_messages.to_sentence
    end
  end

  private

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
end
