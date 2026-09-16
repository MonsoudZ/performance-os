Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :registration, only: %i[new create]
  resources :email_verifications, param: :token, only: %i[create show]
  resources :email_changes, param: :token, only: %i[create show]
  delete "email_changes", to: "email_changes#destroy", as: :cancel_email_change
  root "dashboard#show"

  resource :onboarding, only: :show, controller: "onboarding"
  resource :progress, only: :show, controller: "progress"
  resource :program, only: %i[create update], controller: "programs"
  resource :readiness_check_in, only: :create
  resources :readiness_inputs, only: %i[index edit update]
  resources :goal_periods, only: %i[index create] do
    patch :finish, on: :member
  end
  resource :nutrition, only: :show, controller: "nutrition"
  resource :weekly_review, only: %i[show create]
  resources :wearable_devices, only: %i[index create destroy]
  resources :foods, only: %i[create edit update destroy] do
    collection do
      get :search
      post :import
      post :log
    end
  end
  resources :food_log_entries, only: %i[create update destroy] do
    post :copy_yesterday, on: :collection
  end
  resources :body_metrics, only: %i[create destroy]
  resources :meals, except: :show do
    post :log, on: :member
  end
  # A meal already eaten is already recorded, so keeping it costs a name — the
  # same move as saving a logged session as a workout.
  post "meals/from_log", to: "meals#create_from_log", as: :meal_from_log
  resources :mesocycles, only: %i[index create] do
    patch :finish, on: :member
  end
  resources :exercises, only: %i[index show new create]
  resources :exercise_prescriptions, only: %i[index new create edit update] do
    patch :finish, on: :member
  end
  resources :workout_templates, except: :show
  resources :workout_sessions, only: %i[index new create show edit update destroy]
  # A logged session and a template hold the same thing — which exercises, in
  # which order — so one can be made from the other. The template is what gets
  # created, so the action lives with templates.
  post "workout_sessions/:workout_session_id/save_as_workout",
    to: "workout_templates#create_from_session", as: :save_workout_session_as_workout
  resources :conditioning_sessions, only: %i[index create destroy]
  resources :coach_narratives, only: :create
  resources :coaching_decisions, only: :show
  resource :profile, only: %i[edit update destroy]
  resources :active_sessions, only: :destroy
  delete "active_sessions", to: "active_sessions#destroy_others", as: :other_active_sessions
  resource :account_export, only: :show, controller: "account_exports"
  post "push_subscriptions", to: "push_subscriptions#create"
  delete "push_subscriptions", to: "push_subscriptions#destroy"

  namespace :api do
    namespace :v1 do
      # Public and throttled: the catalog belongs to nobody, and a client needs
      # it before it has anywhere to sign in to.
      resources :exercises, only: :index

      resource :wearable_sync, only: :create, controller: "wearable_sync"

      # A native client signs in here and holds the token it gets back. The
      # session it creates is a device in the user's list like any other.
      resource :session, only: %i[create destroy], controller: "sessions"
      resource :profile, only: :show, controller: "profiles"
      resources :workout_templates, only: %i[index show]
      resources :workout_sessions, only: %i[index show create]

      # The day's eating in one request, and the writes that change it.
      resource :nutrition, only: :show, controller: "nutrition"
      resources :foods, only: %i[index create] do
        # Every call here is an outbound request to Open Food Facts, so it
        # carries its own throttle in Rack::Attack.
        get :search, on: :collection
      end
      resources :food_log_entries, only: %i[create update destroy] do
        post :copy_yesterday, on: :collection
      end
      resources :meals, only: :index do
        post :log, on: :member
      end

      # A weigh-in, and the trend and expenditure estimate it feeds.
      resources :body_metrics, only: %i[index create destroy]

      # The four ratings are the part only the user knows, so this reads back
      # what was answered and never guesses the rest.
      resource :readiness_check_in, only: %i[show create], controller: "readiness_check_ins"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
