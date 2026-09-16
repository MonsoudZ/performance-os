class MealsController < ApplicationController
  include NutritionWorkspace
  include NutritionRecomputable

  before_action :set_meal, only: %i[edit update destroy log]

  def index
    @meals = Current.user.meals.includes(meal_items: :food).order(:name)
  end

  def new
    @meal = Current.user.meals.new
    @meal.meal_items.build(position: 1)
    prepare_form
  end

  def create
    @meal = Current.user.meals.new(meal_params)
    @meal.renumber_items

    if @meal.save
      redirect_to meals_path, notice: "#{@meal.name} saved."
    else
      prepare_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prepare_form
  end

  def update
    @meal.assign_attributes(meal_params)
    @meal.renumber_items

    if @meal.save
      redirect_to meals_path, notice: "#{@meal.name} updated."
    else
      prepare_form
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @meal.destroy!
    redirect_to meals_path, notice: "#{@meal.name} deleted.", status: :see_other
  end

  # One tap logs every food in the meal.
  def log
    result = MealLogger.new(@meal).call
    date = Current.user.local_date
    recompute_nutrition(date)

    respond_after_logging(date, "#{@meal.name} logged · #{result.entries.size} #{'item'.pluralize(result.entries.size)}.")
  end

  # Keep a meal already eaten, the way a logged session becomes a workout.
  def create_from_log
    entries = entries_for(Date.iso8601(params[:date].to_s), params[:meal_type])
    meal = MealFromLoggedEntries.new(Current.user, entries, name: params[:name]).call

    if meal.persisted?
      redirect_to edit_meal_path(meal), notice: "#{meal.name} saved. Adjust the portions here."
    else
      redirect_to nutrition_path, alert: meal.errors.full_messages.to_sentence
    end
  rescue Date::Error
    # A date that will not parse means the form was tampered with rather than
    # mistyped, but an error page is still the wrong answer to it.
    redirect_to nutrition_path, alert: "That is not a date."
  end

  private

  def set_meal
    @meal = Current.user.meals.includes(meal_items: :food).find(params[:id])
  end

  def prepare_form
    @foods = Food.available_to(Current.user)
  end

  def meal_params
    params.require(:meal).permit(:name, meal_items_attributes: %i[id food_id quantity_grams position _destroy])
  end

  def entries_for(date, meal_type)
    scope = Current.user.food_log_entries.where(logged_at: Current.user.local_day_range(date))
    scope = scope.where(meal_type: meal_type) if meal_type.present?
    scope.includes(:food).order(:logged_at).to_a
  end

  def respond_after_logging(date, notice)
    respond_to do |format|
      format.turbo_stream do
        load_nutrition_workspace(date)
        flash.now[:notice] = notice
        render turbo_stream: turbo_stream.replace("nutrition_log", partial: "nutrition/log_workspace")
      end
      format.html { redirect_to nutrition_path, notice: }
    end
  end
end
