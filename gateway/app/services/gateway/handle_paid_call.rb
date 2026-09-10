# frozen_string_literal: true

module Gateway
  # The whole x402 loop for one request, in the fixed order
  # 402 → verify → upstream → settle → record. Returns a Result whose data is
  # ready to render: { status:, body:, headers:, content_type: }.
  class HandlePaidCall
    def initialize(service:, payment_header:, body:, headers: {}, adapter: Payments::Adapters.current)
      @service = service
      @payment_header = payment_header
      @body = body
      @headers = headers
      @adapter = adapter
    end

    def call
      built = Payments::BuildRequirements.new(service: @service).call
      return built if built.failure?

      requirements = built[:requirements]
      payload = Payments::Payload.from_header(@payment_header)
      return payment_required(requirements, "Payment required") if payload.nil?

      verified = Payments::VerifyPayment.new(payload: payload, requirements: requirements, adapter: @adapter).call
      return payment_required(requirements, verified.error) if verified.failure?

      upstream = Gateway::ProxyCall.new(service: @service, body: @body, headers: @headers).call
      return Result.failure(upstream.error, code: upstream.code, data: { status: 502, body: { error: upstream.error }.to_json }) if upstream.failure?

      settled = Payments::SettlePayment.new(payload: payload, requirements: requirements, adapter: @adapter).call
      return payment_required(requirements, settled.error) if settled.failure?

      receipt = settled[:receipt]
      recorded = Ledger::RecordTransaction.new(service: @service, requirements: requirements, receipt: receipt, upstream: upstream.data).call
      Rails.logger.error("ledger: #{recorded.error}") if recorded.failure? # never fail a paid, settled call over bookkeeping

      Result.success(status: upstream[:status], body: upstream[:body], content_type: upstream[:content_type],
                     headers: { Payments::Receipt::HEADER => receipt.to_header }, call: recorded[:call])
    end

    private

    def payment_required(requirements, error)
      body = Payments::BuildRequirements.body_for(service: @service, requirements: requirements).merge(error: error)
      Result.failure(error, code: :payment_required, data: { status: 402, body: body.to_json, content_type: "application/json" })
    end
  end
end
