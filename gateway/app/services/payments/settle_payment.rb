# frozen_string_literal: true

module Payments
  # Submits the payment on-chain through the adapter. Called only after the
  # upstream call succeeded (see .claude/rules/payments.md).
  class SettlePayment
    def initialize(payload:, requirements:, adapter: Adapters.current)
      @payload = payload
      @requirements = requirements
      @adapter = adapter
    end

    def call
      @adapter.settle(payload: @payload, requirements: @requirements)
    end
  end
end
