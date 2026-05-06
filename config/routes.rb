Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  resource :walk, only: :show
  get "privacy" => "pages#privacy", as: :privacy
  get "terms" => "pages#terms", as: :terms
  root "pages#home"
end
