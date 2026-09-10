Rails.application.routes.draw do
  mount RailsIcons::Engine, at: '/rails_icons'
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Living style guide (ViewComponent previews)
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?

  # Public catalog. `/s/:slug` is also the base of every paid endpoint
  # (the x402 paywall middleware will sit in front of POST /s/:slug/*path).
  root "catalog#index"
  get "s/:slug", to: "catalog#show", as: :service
  # The paid endpoint itself: 402 → X-PAYMENT → verify → upstream → settle.
  post "s/:slug", to: "paid_calls#create", as: :paid_call

  # Pages
  get "docs", to: "pages#docs"
  get "sell", to: "pages#sell"
  post "sell", to: "seller_inquiries#create", as: :seller_inquiries
  get "sign_in", to: "pages#sign_in"

  # Machine-readable catalog (read by mcp-hub)
  namespace :api do
    namespace :v1 do
      get "catalog", to: "catalog#index"
      get "catalog/:slug", to: "catalog#show", as: :catalog_service
    end
  end
end
