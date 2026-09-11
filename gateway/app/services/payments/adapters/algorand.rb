# frozen_string_literal: true

module Payments
  module Adapters
    # Talks to the GoPlausible x402 facilitator. Request/response shapes are in
    # docs/x402-algorand.md — update that file if the facilitator differs.
    class Algorand < Base
      OPEN_TIMEOUT = 5
      TIMEOUT = 30

      def initialize(base_url: Rails.configuration.x402.facilitator_url, connection: nil)
        @connection = connection || build_connection(base_url)
      end

      def verify(payload:, requirements:, extensions: nil)
        body = post("/verify", payload, requirements, extensions)
        return body if body.is_a?(Result)

        if body["isValid"]
          Result.success(payer: body["payer"])
        else
          Result.failure(body["invalidReason"] || "payment invalid", code: :invalid_payment)
        end
      end

      def settle(payload:, requirements:, extensions: nil)
        body = post("/settle", payload, requirements, extensions)
        return body if body.is_a?(Result)

        receipt = Receipt.new(success: body["success"] == true, transaction: body["transaction"],
                              network: body["network"], payer: body["payer"], error_reason: body["errorReason"])
        return Result.failure(receipt.error_reason || "settlement failed", code: :settlement_failed, data: { receipt: receipt }) unless receipt.success

        Result.success(receipt: receipt)
      end

      private

      def post(path, payload, requirements, extensions)
        response = @connection.post(path) do |req|
          req.body = { x402Version: 2, paymentPayload: envelope(payload, requirements, extensions),
                       paymentRequirements: requirements.to_spec_h }.to_json
        end
        return Result.failure("facilitator #{path} returned #{response.status}", code: :facilitator_error) unless response.success?

        JSON.parse(response.body)
      rescue Faraday::Error => e
        Result.failure("facilitator unreachable: #{e.message}", code: :facilitator_unreachable)
      rescue JSON::ParserError
        Result.failure("facilitator returned invalid JSON", code: :facilitator_error)
      end

      # x402 v2 PaymentPayload: the facilitator reads the resource URL, the
      # challenge tag (accepted.extra.tag) and the discovery extension from the
      # payload itself. Strict v2 clients send them; fill in for those that
      # only send `payload` (v1-style), so tagging and cataloging still happen.
      def envelope(payload, requirements, extensions)
        h = payload.to_h.dup
        h["x402Version"] ||= 2
        h["resource"] ||= requirements.resource_info
        h["accepted"] ||= requirements.to_spec_h
        h["extensions"] ||= extensions if extensions
        h
      end

      def build_connection(base_url)
        Faraday.new(url: base_url, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }) do |f|
          f.options.open_timeout = OPEN_TIMEOUT
          f.options.timeout = TIMEOUT
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
