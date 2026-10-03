Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]

  resource :pool, only: %i[edit update]
  resource :location_search, only: :create
  resource :setpoint, only: :update
  resources :checks, only: :create
  resources :text_messages, only: :index

  # Twilio inbound SMS webhook (configure as the "A message comes in" URL)
  post "twilio/sms" => "twilio_webhooks#create", as: :twilio_sms

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
