# frozen_string_literal: true

module Payments
  # Result of a settlement: what we record in the ledger and hand back in
  # X-PAYMENT-RESPONSE (base64 of `to_h`).
  class Receipt < Data.define(:success, :transaction, :network, :payer, :error_reason)
    HEADER = "X-PAYMENT-RESPONSE"

    def to_h
      { success: success, transaction: transaction, network: network, payer: payer, errorReason: error_reason }.compact
    end

    def to_header = Base64.strict_encode64(to_h.to_json)
  end
end
