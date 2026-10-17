require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Gateway
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "UTC"
    config.i18n.default_locale = :en
    config.i18n.available_locales = [ :en, :es ]

    # Render's edge is Cloudflare, so every request reaches us through a
    # Cloudflare server and `request.remote_ip` was that server's address:
    # two calls a second apart from one machine got two "callers", both in
    # Miami. Trusting Cloudflare's ranges makes Rails read the caller from
    # X-Forwarded-For instead, for the free trial, the rate limits and the
    # visitor locations alike. A forged X-Forwarded-For does not help: the
    # address Cloudflare appends is the last untrusted one, and that wins.
    # Ranges from https://www.cloudflare.com/ips (checked Oct 17, 2026).
    CLOUDFLARE_RANGES = %w[
      173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18
      108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17
      162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
      2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32
      2a06:98c0::/29 2c0f:f248::/32
    ].freeze
    config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + CLOUDFLARE_RANGES.map { |range| IPAddr.new(range) }

    # ViewComponent previews double as Lookbook pages and as fixtures for tests.
    config.view_component.previews.paths << Rails.root.join("test/components/previews")
    config.view_component.previews.default_layout = "component_preview"
  end
end
