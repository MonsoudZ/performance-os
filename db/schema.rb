# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_10_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "body_metrics", force: :cascade do |t|
    t.decimal "body_fat_pct", precision: 4, scale: 1
    t.datetime "created_at", null: false
    t.date "measured_on", null: false
    t.string "source", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "weight_kg", precision: 6, scale: 2
    t.index ["user_id", "measured_on"], name: "index_body_metrics_on_user_id_and_measured_on"
    t.index ["user_id"], name: "index_body_metrics_on_user_id"
    t.check_constraint "body_fat_pct IS NULL OR body_fat_pct >= 0::numeric AND body_fat_pct <= 100::numeric", name: "body_metrics_body_fat_check"
    t.check_constraint "weight_kg IS NULL OR weight_kg > 0::numeric", name: "body_metrics_weight_check"
  end

  create_table "coaching_decision_links", force: :cascade do |t|
    t.bigint "child_decision_id", null: false
    t.datetime "created_at", null: false
    t.bigint "parent_decision_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["child_decision_id"], name: "index_coaching_decision_links_on_child_decision_id"
    t.index ["parent_decision_id", "child_decision_id"], name: "index_coaching_decision_links_unique", unique: true
    t.index ["parent_decision_id"], name: "index_coaching_decision_links_on_parent_decision_id"
    t.check_constraint "role::text = ANY (ARRAY['readiness'::character varying, 'progression'::character varying, 'nutrition'::character varying, 'weekly_review'::character varying]::text[])", name: "coaching_decision_links_role_check"
  end

  create_table "coaching_decisions", force: :cascade do |t|
    t.jsonb "citations", default: [], null: false
    t.string "confidence"
    t.datetime "created_at", null: false
    t.string "decision_type", null: false
    t.jsonb "inputs", null: false
    t.jsonb "output", null: false
    t.string "rule_key", null: false
    t.string "rule_version", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "decision_type", "created_at"], name: "index_decisions_on_user_type_and_created_at"
    t.index ["user_id"], name: "index_coaching_decisions_on_user_id"
    t.check_constraint "confidence::text = ANY (ARRAY['low'::character varying, 'moderate'::character varying, 'high'::character varying]::text[])", name: "coaching_decisions_confidence_check"
  end

  create_table "daily_readiness_inputs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "fatigue"
    t.decimal "hrv_sdnn_ms", precision: 6, scale: 2
    t.date "metric_date", null: false
    t.integer "resting_hr"
    t.integer "sleep_minutes"
    t.integer "sleep_quality"
    t.integer "soreness"
    t.string "source", default: "manual", null: false
    t.integer "stress"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "metric_date"], name: "index_daily_readiness_inputs_on_user_id_and_metric_date", unique: true
    t.index ["user_id"], name: "index_daily_readiness_inputs_on_user_id"
    t.check_constraint "fatigue >= 1 AND fatigue <= 5", name: "readiness_inputs_fatigue_check"
    t.check_constraint "sleep_quality >= 1 AND sleep_quality <= 5", name: "readiness_inputs_sleep_quality_check"
    t.check_constraint "soreness >= 1 AND soreness <= 5", name: "readiness_inputs_soreness_check"
    t.check_constraint "stress >= 1 AND stress <= 5", name: "readiness_inputs_stress_check"
  end

  create_table "exercise_muscle_contributions", id: false, force: :cascade do |t|
    t.bigint "exercise_id", null: false
    t.decimal "fraction", precision: 3, scale: 2, null: false
    t.bigint "muscle_group_id", null: false
    t.string "role", null: false
    t.index ["exercise_id", "muscle_group_id"], name: "index_exercise_muscle_contributions_unique", unique: true
    t.index ["exercise_id"], name: "index_exercise_muscle_contributions_on_exercise_id"
    t.index ["muscle_group_id"], name: "index_exercise_muscle_contributions_on_muscle_group_id"
    t.check_constraint "fraction > 0::numeric AND fraction <= 1::numeric", name: "exercise_muscle_contributions_fraction_check"
    t.check_constraint "role::text = ANY (ARRAY['primary'::character varying, 'secondary'::character varying]::text[])", name: "exercise_muscle_contributions_role_check"
  end

  create_table "exercise_prescriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "ended_on"
    t.bigint "exercise_id", null: false
    t.decimal "increment_kg", precision: 5, scale: 2, null: false
    t.integer "rep_max", null: false
    t.integer "rep_min", null: false
    t.date "started_on", null: false
    t.decimal "target_rir_max", precision: 3, scale: 1, null: false
    t.decimal "target_rir_min", precision: 3, scale: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "working_sets", null: false
    t.index ["exercise_id"], name: "index_exercise_prescriptions_on_exercise_id"
    t.index ["user_id", "exercise_id"], name: "index_active_prescription_per_user_exercise", unique: true, where: "(ended_on IS NULL)"
    t.index ["user_id"], name: "index_exercise_prescriptions_on_user_id"
    t.check_constraint "ended_on IS NULL OR ended_on >= started_on", name: "exercise_prescriptions_dates_check"
    t.check_constraint "increment_kg > 0::numeric AND working_sets > 0", name: "exercise_prescriptions_progression_check"
    t.check_constraint "rep_min > 0 AND rep_max >= rep_min", name: "exercise_prescriptions_rep_range_check"
    t.check_constraint "target_rir_min >= 0::numeric AND target_rir_max >= target_rir_min", name: "exercise_prescriptions_rir_range_check"
  end

  create_table "exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_unit", default: "kg", null: false
    t.boolean "is_compound", default: false, null: false
    t.string "modality", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id", "name"], name: "index_exercises_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_exercises_on_user_id"
    t.check_constraint "default_unit::text = ANY (ARRAY['kg'::character varying, 'reps'::character varying, 'seconds'::character varying, 'meters'::character varying]::text[])", name: "exercises_default_unit_check"
    t.check_constraint "modality::text = ANY (ARRAY['barbell'::character varying, 'dumbbell'::character varying, 'machine'::character varying, 'bodyweight'::character varying, 'cable'::character varying, 'other'::character varying]::text[])", name: "exercises_modality_check"
  end

  create_table "expenditure_estimates", id: false, force: :cascade do |t|
    t.datetime "computed_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "confidence"
    t.date "estimate_date", null: false
    t.decimal "estimated_tdee", precision: 7, scale: 1, null: false
    t.decimal "intake_kcal", precision: 7, scale: 1
    t.decimal "trend_weight_kg", precision: 6, scale: 2
    t.bigint "user_id", null: false
    t.index ["user_id", "estimate_date"], name: "index_expenditure_estimates_on_user_id_and_estimate_date", unique: true
    t.index ["user_id"], name: "index_expenditure_estimates_on_user_id"
    t.check_constraint "confidence::text = ANY (ARRAY['low'::character varying, 'moderate'::character varying, 'high'::character varying]::text[])", name: "expenditure_estimates_confidence_check"
  end

  create_table "food_log_entries", force: :cascade do |t|
    t.decimal "carb_g", precision: 6, scale: 1, null: false
    t.datetime "created_at", null: false
    t.decimal "fat_g", precision: 6, scale: 1, null: false
    t.bigint "food_id"
    t.decimal "kcal", precision: 7, scale: 1, null: false
    t.datetime "logged_at", null: false
    t.decimal "protein_g", precision: 6, scale: 1, null: false
    t.decimal "quantity_grams", precision: 7, scale: 1, null: false
    t.string "source", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["food_id"], name: "index_food_log_entries_on_food_id"
    t.index ["user_id", "logged_at"], name: "index_food_log_entries_on_user_id_and_logged_at"
    t.index ["user_id"], name: "index_food_log_entries_on_user_id"
    t.check_constraint "quantity_grams > 0::numeric AND kcal >= 0::numeric AND protein_g >= 0::numeric AND carb_g >= 0::numeric AND fat_g >= 0::numeric", name: "food_log_entries_values_check"
  end

  create_table "foods", force: :cascade do |t|
    t.string "barcode"
    t.string "brand"
    t.decimal "carb_g", precision: 6, scale: 1, null: false
    t.datetime "created_at", null: false
    t.decimal "fat_g", precision: 6, scale: 1, null: false
    t.decimal "kcal", precision: 7, scale: 1, null: false
    t.string "name", null: false
    t.decimal "protein_g", precision: 6, scale: 1, null: false
    t.decimal "serving_grams", precision: 7, scale: 1, null: false
    t.string "source", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["barcode"], name: "index_foods_on_barcode", where: "(barcode IS NOT NULL)"
    t.index ["user_id", "name", "brand"], name: "index_foods_on_user_id_and_name_and_brand"
    t.index ["user_id"], name: "index_foods_on_user_id"
    t.check_constraint "serving_grams > 0::numeric AND kcal >= 0::numeric AND protein_g >= 0::numeric AND carb_g >= 0::numeric AND fat_g >= 0::numeric", name: "foods_nutrition_values_check"
    t.check_constraint "source::text = ANY (ARRAY['manual'::character varying, 'barcode'::character varying, 'import'::character varying, 'verified'::character varying]::text[])", name: "foods_source_check"
  end

  create_table "goal_periods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "ended_on"
    t.string "goal_type", null: false
    t.jsonb "params", default: {}, null: false
    t.date "started_on", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_goal_periods_on_active_user", unique: true, where: "(ended_on IS NULL)"
    t.index ["user_id"], name: "index_goal_periods_on_user_id"
    t.check_constraint "ended_on IS NULL OR ended_on >= started_on", name: "goal_periods_dates_check"
    t.check_constraint "goal_type::text = ANY (ARRAY['build_muscle'::character varying, 'lose_fat'::character varying, 'increase_strength'::character varying, 'athletic_performance'::character varying, 'vertical_jump'::character varying, 'marathon'::character varying, 'longevity'::character varying]::text[])", name: "goal_periods_goal_type_check"
  end

  create_table "muscle_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_muscle_groups_on_name", unique: true
  end

  create_table "readiness_scores", id: false, force: :cascade do |t|
    t.jsonb "components", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "score", null: false
    t.date "score_date", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "score_date"], name: "index_readiness_scores_on_user_id_and_score_date", unique: true
    t.index ["user_id"], name: "index_readiness_scores_on_user_id"
    t.check_constraint "score >= 0 AND score <= 100", name: "readiness_scores_score_check"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "set_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.virtual "estimated_1rm_kg", type: :decimal, precision: 7, scale: 2, as: "(weight_kg * ((1)::numeric + ((reps)::numeric / (30)::numeric)))", stored: true
    t.bigint "exercise_id", null: false
    t.boolean "is_warmup", default: false, null: false
    t.integer "reps"
    t.decimal "rir", precision: 3, scale: 1
    t.decimal "rpe", precision: 3, scale: 1
    t.integer "set_index", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight_kg", precision: 6, scale: 2
    t.bigint "workout_session_id", null: false
    t.index ["exercise_id", "created_at"], name: "index_set_entries_on_exercise_id_and_created_at"
    t.index ["exercise_id"], name: "index_set_entries_on_exercise_id"
    t.index ["workout_session_id", "exercise_id", "set_index"], name: "index_set_entries_on_session_exercise_and_index", unique: true
    t.index ["workout_session_id"], name: "index_set_entries_on_workout_session_id"
    t.check_constraint "reps IS NULL OR reps > 0", name: "set_entries_reps_check"
    t.check_constraint "rir IS NULL OR rir >= 0::numeric", name: "set_entries_rir_check"
    t.check_constraint "rpe IS NULL OR rpe >= 0::numeric AND rpe <= 10::numeric", name: "set_entries_rpe_check"
    t.check_constraint "set_index > 0", name: "set_entries_index_check"
  end

  create_table "users", force: :cascade do |t|
    t.date "birth_date"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.decimal "height_cm", precision: 5, scale: 1
    t.string "password_digest", null: false
    t.string "sex"
    t.string "time_zone", default: "UTC", null: false
    t.string "unit_system", default: "metric", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.check_constraint "sex::text = ANY (ARRAY['male'::character varying, 'female'::character varying, 'unspecified'::character varying]::text[])", name: "users_sex_check"
    t.check_constraint "unit_system::text = ANY (ARRAY['metric'::character varying, 'imperial'::character varying]::text[])", name: "users_unit_system_check"
  end

  create_table "wearable_devices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.string "platform", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "external_id"], name: "index_wearable_devices_on_user_id_and_external_id", unique: true
    t.index ["user_id"], name: "index_wearable_devices_on_user_id"
    t.check_constraint "platform::text = 'ios_healthkit'::text", name: "wearable_devices_platform_check"
  end

  create_table "wearable_samples", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.string "external_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "metric_type", null: false
    t.datetime "started_at", null: false
    t.string "unit", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "value", precision: 10, scale: 3
    t.bigint "wearable_device_id", null: false
    t.index ["user_id", "metric_type", "started_at"], name: "idx_on_user_id_metric_type_started_at_c4f798ed12"
    t.index ["user_id"], name: "index_wearable_samples_on_user_id"
    t.index ["wearable_device_id", "external_id"], name: "index_wearable_samples_on_wearable_device_id_and_external_id", unique: true
    t.index ["wearable_device_id"], name: "index_wearable_samples_on_wearable_device_id"
    t.check_constraint "metric_type::text = ANY (ARRAY['hrv_sdnn_ms'::character varying, 'resting_hr_bpm'::character varying, 'sleep_asleep'::character varying]::text[])", name: "wearable_samples_metric_type_check"
    t.check_constraint "value IS NULL OR value >= 0::numeric", name: "wearable_samples_value_check"
  end

  create_table "weight_trends", id: false, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "ewma_kg", precision: 6, scale: 2, null: false
    t.decimal "raw_kg", precision: 6, scale: 2
    t.date "trend_date", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "trend_date"], name: "index_weight_trends_on_user_id_and_trend_date", unique: true
    t.index ["user_id"], name: "index_weight_trends_on_user_id"
  end

  create_table "workout_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.text "notes"
    t.datetime "performed_at", null: false
    t.decimal "session_rpe", precision: 3, scale: 1
    t.jsonb "template_snapshot", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_template_id"
    t.index ["user_id", "performed_at"], name: "index_workout_sessions_on_user_id_and_performed_at"
    t.index ["user_id"], name: "index_workout_sessions_on_user_id"
    t.index ["workout_template_id"], name: "index_workout_sessions_on_workout_template_id"
    t.check_constraint "session_rpe IS NULL OR session_rpe >= 0::numeric AND session_rpe <= 10::numeric", name: "workout_sessions_rpe_check"
  end

  create_table "workout_template_exercises", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "exercise_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.bigint "workout_template_id", null: false
    t.index ["exercise_id"], name: "index_workout_template_exercises_on_exercise_id"
    t.index ["workout_template_id", "exercise_id"], name: "index_template_exercises_unique", unique: true
    t.index ["workout_template_id", "position"], name: "index_template_exercises_position"
    t.index ["workout_template_id"], name: "index_workout_template_exercises_on_workout_template_id"
    t.check_constraint "\"position\" > 0", name: "workout_template_exercises_position_check"
  end

  create_table "workout_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "weekdays", default: [], null: false, array: true
    t.index ["user_id", "name"], name: "index_workout_templates_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_workout_templates_on_user_id"
  end

  add_foreign_key "body_metrics", "users"
  add_foreign_key "coaching_decision_links", "coaching_decisions", column: "child_decision_id", on_delete: :restrict
  add_foreign_key "coaching_decision_links", "coaching_decisions", column: "parent_decision_id", on_delete: :cascade
  add_foreign_key "coaching_decisions", "users"
  add_foreign_key "daily_readiness_inputs", "users"
  add_foreign_key "exercise_muscle_contributions", "exercises"
  add_foreign_key "exercise_muscle_contributions", "muscle_groups"
  add_foreign_key "exercise_prescriptions", "exercises"
  add_foreign_key "exercise_prescriptions", "users"
  add_foreign_key "exercises", "users"
  add_foreign_key "expenditure_estimates", "users"
  add_foreign_key "food_log_entries", "foods"
  add_foreign_key "food_log_entries", "users"
  add_foreign_key "foods", "users"
  add_foreign_key "goal_periods", "users"
  add_foreign_key "readiness_scores", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "set_entries", "exercises"
  add_foreign_key "set_entries", "workout_sessions", on_delete: :cascade
  add_foreign_key "wearable_devices", "users"
  add_foreign_key "wearable_samples", "users"
  add_foreign_key "wearable_samples", "wearable_devices"
  add_foreign_key "weight_trends", "users"
  add_foreign_key "workout_sessions", "users"
  add_foreign_key "workout_sessions", "workout_templates"
  add_foreign_key "workout_template_exercises", "exercises"
  add_foreign_key "workout_template_exercises", "workout_templates"
  add_foreign_key "workout_templates", "users"
end
