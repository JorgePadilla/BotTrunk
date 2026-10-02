# Per-IP throttles in front of the endpoints anyone can hit without paying
# (docs/deploy.md, "Rate limits"). Nothing here blocks a paying agent at a
# realistic pace; it caps what one address can make us do for free:
#
#   paywall_probe  POST /s/:slug with no payment — a 402 costs us a render.
#   paywall_paid   POST /s/:slug with a payment — each one is a facilitator
#                  /verify round trip, valid or not.
#   mcp            POST /mcp — free, read-only, but still work.
#   forms          POST /sell and /service-requests — each sends an email,
#                  and Resend's free tier stops at 100 a day.
#
# GET /s/:slug is the catalog page and is never throttled, nor are CORS
# preflights or /up.
Rails.application.config.x.rate_limits = {
  paywall_probe: { limit: 60, period: 1.minute },
  paywall_paid: { limit: 120, period: 1.minute },
  mcp: { limit: 120, period: 1.minute },
  forms: { limit: 10, period: 1.hour }
}.freeze

class Rack::Attack
  # Counters live in this process. The gateway is one Puma process on one
  # Render instance (WEB_CONCURRENCY unset), so the count is exact and a
  # restart only forgives a minute. With more processes or instances, point
  # this at Solid Cache instead or each one counts on its own.
  cache.store = ActiveSupport::Cache::MemoryStore.new

  class Request < ::Rack::Request
    # The same address TracksEvents records: the client Render's proxy saw,
    # not a forwarded header the client wrote.
    def remote_ip = action_dispatch.remote_ip

    def paywall? = post? && path.match?(%r{\A/s/[^/]+/?\z})

    def paid? = Payments::Payload.header_in(action_dispatch.headers).present?

    private

    def action_dispatch = @action_dispatch ||= ActionDispatch::Request.new(env)
  end

  limits = Rails.application.config.x.rate_limits

  throttle("paywall/probe", **limits[:paywall_probe]) do |req|
    req.remote_ip if req.paywall? && !req.paid?
  end

  throttle("paywall/paid", **limits[:paywall_paid]) do |req|
    req.remote_ip if req.paywall? && req.paid?
  end

  throttle("mcp", **limits[:mcp]) do |req|
    req.remote_ip if req.post? && req.path == "/mcp"
  end

  throttle("forms", **limits[:forms]) do |req|
    req.remote_ip if req.post? && req.path.in?(%w[/sell /service-requests])
  end

  # Agents read the body; browsers on the paywall need the CORS header to see
  # it at all. Throttled requests never reach the paywall, so nothing is charged.
  self.throttled_responder = lambda do |req|
    match = req.env["rack.attack.match_data"]
    retry_after = match[:period] - (match[:epoch_time] % match[:period])
    body = {
      error: "Too many requests from this address. Try again in #{retry_after} seconds.",
      retry_after: retry_after,
      charged: false
    }
    [ 429, { "content-type" => "application/json", "retry-after" => retry_after.to_s, "access-control-allow-origin" => "*" }, [ body.to_json ] ]
  end
end

# One log line per throttled request. Not an analytics event: a database
# write for every blocked request would hand back the load we just refused.
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |event|
  req = event.payload[:request]
  Rails.logger.warn("rack-attack: #{req.env['rack.attack.matched']} throttled #{req.request_method} #{req.path} from #{req.env['rack.attack.match_discriminator']}")
end
