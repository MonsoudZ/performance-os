Rails.application.routes.draw do
  resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :registration, only: %i[new create]
  root "dashboard#show"

  resource :readiness_check_in, only: :create
  resource :nutrition, only: :show, controller: "nutrition"
  resource :weekly_review, only: %i[show create]
  resources :wearable_devices, only: %i[create destroy]
  resources :foods, only: :create
  resources :food_log_entries, only: :create
  resources :body_metrics, only: :create
  resources :exercise_prescriptions, only: %i[index new create]
  resources :workout_sessions, only: %i[new create show]

  namespace :api do
    namespace :v1 do
      resources :exercises, only: :index
      resource :wearable_sync, only: :create, controller: "wearable_sync"
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
