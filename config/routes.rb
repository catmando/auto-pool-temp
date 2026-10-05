Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]

  resource :pool, only: %i[edit update]
  resource :location, only: :update
  resource :location_search, only: :create
  resource :setpoint, only: :update
  resource :water_temp, only: :update
  resource :cover, only: :update
  resource :pump, only: :update
  resources :pool_parties, only: %i[create update destroy]
  resource :phone_verification, only: %i[create update]
  resource :telegram_link, only: %i[create destroy]
  resources :checks, only: :create
  resources :text_messages, only: :index
  resource :lab, only: :show
  resources :forecast_snapshots, only: %i[create destroy]
  resource :test_mode, only: :update

  # Twilio inbound SMS webhook (configure as the "A message comes in" URL)
  post "twilio/sms" => "twilio_webhooks#create", as: :twilio_sms
  # Telegram bot webhook (registered by bin/tunnel or `bin/rails notify:webhooks[url]`)
  post "telegram/webhook" => "telegram_webhooks#create", as: :telegram_webhook

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboards#show"
end
