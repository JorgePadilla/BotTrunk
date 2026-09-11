# frozen_string_literal: true

module Payments
  # Checks the X-PAYMENT payload against the requirements via the adapter.
  # Cheap sanity checks first so obvious junk never reaches the facilitator.
  class VerifyPayment
    def initialize(payload:, requirements:, extensions: nil, adapter: Adapters.current)
      @payload = payload
      @requirements = requirements
      @extensions = extensions
      @adapter = adapter
    end

    def call
      return Result.failure("missing or malformed X-PAYMENT header", code: :invalid_payment) if @payload.nil?
      return Result.failure("unsupported x402 version", code: :invalid_payment) unless @payload.x402_version == 2
      return Result.failure("scheme mismatch", code: :invalid_payment) unless @payload.scheme == @requirements.scheme
      return Result.failure("network mismatch", code: :invalid_payment) unless @payload.network == @requirements.network

      @adapter.verify(payload: @payload, requirements: @requirements, extensions: @extensions)
    end
  end
end
