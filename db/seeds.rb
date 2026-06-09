# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
ExerciseCatalogImporter.new.call

if ENV["SEED_DEMO_USER"] == "true"
  user = User.find_or_initialize_by(email_address: "athlete@performanceos.local")
  user.assign_attributes(
    password: "performance",
    password_confirmation: "performance",
    unit_system: "imperial",
    time_zone: "America/Denver"
  )
  user.save!

  goal = user.goal_periods.find_or_create_by!(ended_on: nil) do |goal|
    goal.goal_type = "build_muscle"
    goal.started_on = user.local_date.beginning_of_week
  end
  goal.update!(
    goal_type: "build_muscle",
    params: goal.params.merge(
      "primary_lift" => "barbell back squat",
      "target_kcal" => 2_800,
      "target_protein_g" => 180
    )
  )

  squat = Exercise.find_by!(user_id: nil, name: "Barbell Back Squat")
  user.exercise_prescriptions.find_or_create_by!(exercise: squat, ended_on: nil) do |prescription|
    prescription.rep_min = 6
    prescription.rep_max = 8
    prescription.target_rir_min = 1
    prescription.target_rir_max = 2
    prescription.increment_kg = 2.5
    prescription.working_sets = 3
    prescription.started_on = user.local_date
  end

  food_data = [
    [ "Chicken Breast", nil, 100, 165, 31, 0, 3.6 ],
    [ "Cooked White Rice", nil, 100, 130, 2.7, 28, 0.3 ],
    [ "Greek Yogurt", nil, 100, 73, 10, 4, 1.9 ],
    [ "Whey Protein", nil, 30, 120, 24, 3, 2 ]
  ]

  food_data.each do |name, brand, serving_grams, kcal, protein, carbs, fat|
    Food.find_or_create_by!(user_id: nil, name: name, brand: brand) do |food|
      food.serving_grams = serving_grams
      food.kcal = kcal
      food.protein_g = protein
      food.carb_g = carbs
      food.fat_g = fat
      food.source = "verified"
    end
  end

  today_input = user.daily_readiness_inputs.find_by(metric_date: user.local_date)
  if today_input && user.coaching_decisions.where(decision_type: "daily_readiness")
      .where("inputs ->> 'metric_date' = ?", user.local_date.iso8601).none?
    user.readiness_scores.find_by(score_date: user.local_date)&.destroy!
    ReadinessEvaluator.new(today_input).call
  end

  NutritionEvaluator.new(user).call
  DailyTrainingOrchestrator.new(user).call
end
