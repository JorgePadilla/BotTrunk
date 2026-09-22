Rails.application.routes.draw do
  mount RailsIcons::Engine, at: "/rails_icons"
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
  match "s/:slug", to: "paid_calls#preflight", via: :options

  # Pages
  get "docs", to: "pages#docs"
  get "sell", to: "pages#sell"
  post "sell", to: "seller_inquiries#create", as: :seller_inquiries
  post "service-requests", to: "service_requests#create", as: :service_requests
  get "connect", to: "pages#connect"
  get "sign_in", to: "pages#sign_in"
  get "llms.txt", to: "pages#llms", as: :llms, format: false

  # Agent-readable files the x402 facilitator probes at our origin, plus the
  # ones coding agents read from the domain (guide/discovery). `format: false`
  # keeps ".json" part of the path instead of a Rails format.
  scope path: ".well-known", format: false do
    get "x402", to: "well_known#x402", as: :well_known_x402
    get "agent-card.json", to: "well_known#agent_card", as: :well_known_agent_card
    get "agent.json", to: "well_known#agent_manifest", as: :well_known_agent_manifest
    get "mcp.json", to: "well_known#mcp", as: :well_known_mcp
  end
  get "agents.md", to: "well_known#agents", as: :agents_md, format: false

  # Operator dashboard (HTTP basic auth, see Admin::BaseController)
  namespace :admin do
    # Bare /admin is a convenience entry point: there is no dashboard index,
    # so send it to the page an operator actually wants. 302, not 301, so a
    # real index later is not fighting a permanently cached redirect.
    root to: redirect("/admin/stats", status: 302)
    get "stats", to: "stats#show"
    get "orders", to: "orders#index"
    post "orders/:token/deliver", to: "orders#deliver", as: :deliver_order
    post "orders/:token/refund", to: "orders#refund", as: :refund_order
    post "rates/refresh", to: "rates#refresh", as: :refresh_rates
    get "inquiries", to: "inquiries#index"
    post "inquiries/:id/approve", to: "inquiries#approve", as: :approve_inquiry
    post "inquiries/:id/reject", to: "inquiries#reject", as: :reject_inquiry
    get "requests", to: "requests#index"
    post "requests/:id/answer", to: "requests#answer", as: :answer_request
    post "requests/:id/close", to: "requests#close", as: :close_request
  end

  # Hosted MCP endpoint (mcp.bottrunk.com/mcp; also /mcp on the other hosts).
  # Stateless Streamable HTTP: POST only, JSON in, JSON out.
  post "mcp", to: "mcp#create"
  match "mcp", to: "mcp#preflight", via: :options
  match "mcp", to: "mcp#unsupported", via: [ :get, :delete ]

  # Public status of a human-fulfilled order (free, no bank details)
  get "orders/:token", to: "orders#show", as: :order

  # Machine-readable catalog (read by mcp-hub)
  namespace :api do
    namespace :v1 do
      get "catalog", to: "catalog#index"
      get "catalog/:slug", to: "catalog#show", as: :catalog_service
    end
  end
end
