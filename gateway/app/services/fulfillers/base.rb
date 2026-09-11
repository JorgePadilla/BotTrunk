# frozen_string_literal: true

require "ipaddr"
require "resolv"

module Fulfillers
  # Shared plumbing for BotTrunk's own (in-process) services: the public-URL
  # guard that keeps us out of private networks, one HTTP client, and the
  # Result shapes the gateway expects.
  #
  # A 4xx answer is still `Result.success` — the request reached us and was
  # answered; `Gateway::HandlePaidCall` is what decides never to settle it.
  # Only a genuine upstream failure is a `Result.failure`.
  class Base
    MAX_BYTES = 2_000_000
    OPEN_TIMEOUT = 5
    TIMEOUT = 20
    USER_AGENT = "BotTrunk/0.1 (+https://bottrunk.com/docs)"

    # DNS resolver used for the SSRF check; tests swap it for a fake. The
    # check itself lives in Security::PublicUrl, because the seller form needs
    # the same answer about URLs we will fetch later.
    def self.resolver = Security::PublicUrl.resolver

    def self.resolver=(value)
      Security::PublicUrl.resolver = value
    end

    def initialize(input:, connection: nil)
      @input = input.is_a?(Hash) ? input : {}
      @connection = connection
    end

    private

    attr_reader :input

    def connection
      @connection ||= build_connection
    end

    def build_connection(follow: 3, accept: "text/html,application/xhtml+xml")
      Faraday.new(headers: { "User-Agent" => USER_AGENT, "Accept" => accept }) do |f|
        f.response :follow_redirects, limit: follow if follow
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    # Parses and validates a public http(s) URL from `input[key]`.
    # Returns the URI, or nil after yielding the failure to the caller.
    def public_uri(key = "url")
      uri, problem = Security::PublicUrl.parse(input[key], strict_dns: true)
      return uri if problem.nil?
      return yield bad_request("#{key} must be a public http(s) URL") if problem == :not_http

      # A host that does not resolve gets the same answer as one that resolves
      # into private space: we could not prove it is safe to fetch.
      yield bad_request("#{key} resolves to a private address")
    end

    def json(payload, status: 200) = Result.success(status: status, content_type: "application/json", body: payload.to_json)

    def bad_request(msg) = json({ error: msg }, status: 422)

    def upstream_error(msg) = Result.failure(msg, code: :upstream_error, data: { status: 502, content_type: "application/json", body: { error: msg }.to_json })

    def fetch(uri, accept: "text/html,application/xhtml+xml")
      response = (@connection || build_connection(accept: accept)).get(uri.to_s)
      return [ nil, upstream_error("fetch failed with #{response.status}") ] unless response.success?
      return [ nil, upstream_error("page too large") ] if response.body.to_s.bytesize > MAX_BYTES

      [ response, nil ]
    rescue Faraday::Error => e
      [ nil, upstream_error("fetch failed: #{e.message.truncate(120)}") ]
    end
  end
end
