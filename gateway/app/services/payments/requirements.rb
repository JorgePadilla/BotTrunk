# frozen_string_literal: true

module Payments
  # One entry of the 402 `accepts` array — what the gateway is willing to be paid.
  # Amounts are integer atomic units (µUSDC). Field names follow x402 v2 and the
  # GoPlausible facilitator; see docs/x402-algorand.md.
  Requirements = Data.define(:scheme, :network, :asset, :amount, :pay_to, :max_timeout_seconds,
                             :resource, :description, :mime_type, :extra) do
    def to_h
      {
        scheme: scheme,
        network: network,
        asset: asset,
        amount: amount.to_s,
        payTo: pay_to,
        maxTimeoutSeconds: max_timeout_seconds,
        resource: resource,
        description: description,
        mimeType: mime_type,
        extra: extra
      }
    end

    def self.from_h(h)
      h = h.transform_keys(&:to_s)
      new(scheme: h["scheme"], network: h["network"], asset: h["asset"].to_s, amount: Integer(h["amount"]),
          pay_to: h["payTo"], max_timeout_seconds: h["maxTimeoutSeconds"], resource: h["resource"],
          description: h["description"], mime_type: h["mimeType"], extra: h["extra"] || {})
    end
  end
end
