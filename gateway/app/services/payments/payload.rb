# frozen_string_literal: true

module Payments
  # The decoded X-PAYMENT header. `raw` is the parsed JSON exactly as the client
  # sent it — the facilitator gets it back untouched.
  class Payload < Data.define(:raw)
    HEADER = "X-PAYMENT"

    def self.from_header(value)
      return nil if value.blank?

      json = Base64.strict_decode64(value.strip)
      raw = JSON.parse(json)
      raw.is_a?(Hash) ? new(raw: raw) : nil
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def x402_version = raw["x402Version"]
    def scheme = raw["scheme"]
    def network = raw["network"]
    def to_h = raw
  end
end
