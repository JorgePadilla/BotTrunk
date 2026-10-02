# frozen_string_literal: true

module Payments
  # The decoded X-PAYMENT header. `raw` is the parsed JSON exactly as the client
  # sent it — the facilitator gets it back untouched.
  class Payload < Data.define(:raw)
    HEADER = "X-PAYMENT"
    # x402 v2 renamed the request header; v1 clients still send HEADER.
    V2_HEADER = "PAYMENT-SIGNATURE"

    # The raw payment header from a request, v2 name first. `headers` is
    # anything that looks headers up by their HTTP names
    # (ActionDispatch::Http::Headers), so the controller and the rate limiter
    # ask the same question without knowing what the headers are called.
    def self.header_in(headers)
      headers[V2_HEADER].presence || headers[HEADER].presence
    end

    def self.from_header(value)
      return nil if value.blank?

      json = Base64.strict_decode64(value.strip)
      raw = JSON.parse(json)
      raw.is_a?(Hash) ? new(raw: raw) : nil
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def x402_version = raw["x402Version"]

    # x402 v2 moved the scheme and the network inside `accepted` — a v2
    # PaymentPayload is { x402Version, resource?, accepted, payload,
    # extensions? } with nothing named `scheme` at the top level. v1 put them
    # there. Reading only the top level rejected every strict v2 client,
    # including our own npm package, with "scheme mismatch" before the
    # facilitator was ever asked. Read the v2 place first, keep the v1
    # fallback: both vocabularies pay.
    def accepted = raw["accepted"].is_a?(Hash) ? raw["accepted"] : {}

    def scheme = accepted["scheme"] || raw["scheme"]

    def network = accepted["network"] || raw["network"]

    def to_h = raw
  end
end
