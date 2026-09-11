require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Active Job runs in the web process. The only background work is email, it
  # is best-effort by design (see Notifications::Deliver), and a settled
  # payment is never waiting on it. Adding a worker service and a durable
  # queue is the right move when something has to survive a restart — a payout
  # run, a retrying webhook — not for a receipt.
  config.active_job.queue_adapter = :async

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "bottrunk.com"),
    protocol: "https"
  }

  # SMTP delivery. If SMTP_ADDRESS is not configured, fall back to :test
  # so the worker does not crash on missing env vars.
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address:              ENV.fetch("SMTP_ADDRESS"),
      port:                 ENV.fetch("SMTP_PORT", 587).to_i,
      domain:               ENV.fetch("SMTP_DOMAIN", "bottrunk.com"),
      user_name:            ENV["SMTP_USER_NAME"],
      password:             ENV["SMTP_PASSWORD"],
      authentication:       :plain,
      enable_starttls_auto: true
    }
  else
    Rails.logger&.warn("[mail] SMTP_ADDRESS not set - using :test delivery. No emails will be sent.")
    config.action_mailer.delivery_method = :test
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = false
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # Hosts we answer to (the paid endpoint and the site). Requests to other
  # Host headers get a 403 instead of reaching the app.
  config.hosts = [ "api.bottrunk.com", "mcp.bottrunk.com", "bottrunk.com", "www.bottrunk.com", /.*\.onrender\.com/ ]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
