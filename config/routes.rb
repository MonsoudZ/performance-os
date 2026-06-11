Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :registration, only: %i[new create]
  root "dashboard#show"

  resource :onboarding, only: :show, controller: "onboarding"
  resource :progress, only: :show, controller: "progress"
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
  resources :mesocycles, only: %i[index create] do
    patch :finish, on: :member
  end
  resources :exercises, only: %i[new create]
  resources :exercise_prescriptions, only: %i[index new create edit update] do
    patch :finish, on: :member
  end
  resources :workout_templates, except: :show
  resources :workout_sessions, only: %i[new create show edit update destroy]
  resources :conditioning_sessions, only: %i[index create destroy]
  resource :profile, only: :update
  post "push_subscriptions", to: "push_subscriptions#create"
  delete "push_subscriptions", to: "push_subscriptions#destroy"

  namespace :api do
    namespace :v1 do
      resources :exercises, only: :index
      resource :wearable_sync, only: :create, controller: "wearable_sync"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
