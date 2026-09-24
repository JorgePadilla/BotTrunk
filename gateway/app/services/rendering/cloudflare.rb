# frozen_string_literal: true

module Rendering
  # Headless rendering through Cloudflare Browser Rendering.
  #
  # Why a third party rather than Chromium in this container: a render is
  # 300-500 MB of RAM, and an OOM here would take down `deposit-bac` and every
  # other paid endpoint with it. A 29-cent scrape must never be able to kill a
  # 410-dollar deposit. The free tier is ~5 browser hours a month (~6,000
  # renders at three seconds each), and overage is $2/browser-hour, about
  # $0.0017 a render — so the margin holds even if this gets popular.
  #
  # Actions map onto the quick-action endpoints: content (rendered HTML),
  # screenshot (PNG), pdf (PDF). `call` returns [payload, failure].
  class Cloudflare
    ENDPOINT = "https://api.cloudflare.com/client/v4/accounts/%<account>s/browser-rendering/%<action>s"
    ACTIONS = %w[content screenshot pdf].freeze
    TIMEOUT = 45   # a cold browser plus a slow page; well past Base::TIMEOUT
    OPEN_TIMEOUT = 5
    MAX_BYTES = 8_000_000

    class << self
      def token = ENV["CLOUDFLARE_API_TOKEN"].presence
      def account_id = ENV["CLOUDFLARE_ACCOUNT_ID"].presence
      def configured? = token.present? && account_id.present?
    end

    def initialize(action:, url:, options: {}, connection: nil)
      raise ArgumentError, "unknown action #{action}" unless ACTIONS.include?(action.to_s)

      @action = action.to_s
      @url = url.to_s
      @options = options.compact
      @connection = connection
    end

    # [payload, failure]. payload is a String: HTML for content, raw bytes for
    # screenshot and pdf. failure is nil, or a message for the caller to wrap.
    def call
      return [ nil, "rendering is not configured" ] unless self.class.configured?

      response = connection.post(endpoint_url) do |req|
        req.headers["Authorization"] = "Bearer #{self.class.token}"
        req.headers["Content-Type"] = "application/json"
        req.body = { url: @url }.merge(@options).to_json
      end

      return [ nil, "renderer answered #{response.status}" ] unless response.success?

      body = response.body.to_s
      return [ nil, "rendered page too large" ] if body.bytesize > MAX_BYTES

      unwrap(response, body)
    rescue Faraday::Error => e
      [ nil, "renderer unreachable: #{e.message.truncate(120)}" ]
    end

    private

    def endpoint_url = format(ENDPOINT, account: self.class.account_id, action: @action)

    # Cloudflare's v4 API usually wraps JSON responses as
    # { success:, errors:, messages:, result: }, but the binary actions answer
    # with the bytes directly. Rather than depend on which, look at what came
    # back: an envelope is unwrapped, anything else is passed through.
    def unwrap(response, body)
      return [ body, nil ] unless response.headers["content-type"].to_s.include?("json")

      parsed = JSON.parse(body)
      return [ body, nil ] unless parsed.is_a?(Hash) && parsed.key?("result")
      return [ nil, error_from(parsed) ] if parsed["success"] == false

      [ parsed["result"].to_s, nil ]
    rescue JSON::ParserError
      [ body, nil ]
    end

    def error_from(parsed)
      messages = Array(parsed["errors"]).filter_map { |e| e.is_a?(Hash) ? e["message"] : e }
      messages.any? ? messages.join("; ").truncate(160) : "renderer refused the page"
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
