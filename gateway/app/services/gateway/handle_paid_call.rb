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

      extensions = { bazaar: Payments::BuildRequirements.bazaar_extension(@service) }
      verified = Payments::VerifyPayment.new(payload: payload, requirements: requirements, extensions: extensions, adapter: @adapter).call
      return payment_required(requirements, verified.error) if verified.failure?

      upstream = Gateway::ProxyCall.new(service: @service, body: @body, headers: @headers).call
      return Result.failure(upstream.error, code: upstream.code, data: { status: 502, body: { error: upstream.error }.to_json }) if upstream.failure?
      return not_charged(upstream) if upstream[:status] >= 400

      settled = Payments::SettlePayment.new(payload: payload, requirements: requirements, extensions: extensions, adapter: @adapter).call
      if settled.failure?
        cancel_order(upstream[:order])
        return payment_required(requirements, settled.error)
      end

      receipt = settled[:receipt]
      recorded = record(requirements, receipt, upstream) # never fail a paid, settled call over bookkeeping
      open_order(upstream[:order], recorded[:call])
      announce_call(recorded[:call])

      Result.success(status: upstream[:status], body: upstream[:body], content_type: upstream[:content_type],
                     headers: { Payments::Receipt::HEADER => receipt.to_header }, call: recorded[:call])
    end

    private

    # The payment is already settled on-chain by the time we get here, so a
    # ledger problem must not turn into an error for the payer. Log it loudly;
    # the transaction id in the receipt lets us reconcile later.
    def record(requirements, receipt, upstream)
      result = Ledger::RecordTransaction.new(service: @service, requirements: requirements, receipt: receipt, upstream: upstream.data).call
      Rails.logger.error("ledger: failed to record settled txn #{receipt.transaction}: #{result.error}") if result.failure?
      result
    rescue StandardError => e
      Rails.logger.error("ledger: exception recording settled txn #{receipt.transaction}: #{e.class}: #{e.message}")
      Result.failure(e.message, code: :ledger_error)
    end

    # The service refused the request (bad input, limits): pass its answer
    # through but never settle — a rejected request costs the payer nothing.
    def not_charged(upstream)
      cancel_order(upstream[:order])
      Result.failure("service rejected the request", code: :rejected_by_service,
                     data: { status: upstream[:status], body: upstream[:body], content_type: upstream[:content_type] })
    end

    # Human-fulfilled services open an order before settlement (so a bad request
    # is refused for free). Once the USDC has settled the order joins the queue.
    def open_order(order, call_row)
      return if order.nil?

      order.update!(status: "pending", call: call_row)
      Notifications::AnnounceOrder.new(order: order).call
    rescue StandardError => e
      Rails.logger.error("orders: could not open #{order.token} after settlement: #{e.class}: #{e.message}")
    end

    # The payer already has their answer; an alert that raises must not turn a
    # successful paid call into a 500.
    def announce_call(call_row)
      return if call_row.nil?

      Notifications::AnnounceCall.new(call: call_row).call
    rescue StandardError => e
      Rails.logger.error("calls: could not announce #{call_row&.transaction_id}: #{e.class}: #{e.message}")
    end

    def cancel_order(order)
      order&.update!(status: "cancelled")
    rescue StandardError => e
      Rails.logger.error("orders: could not cancel #{order.token}: #{e.class}: #{e.message}")
    end

    def payment_required(requirements, error)
      body = Payments::BuildRequirements.body_for(service: @service, requirements: requirements).merge(error: error)
      Result.failure(error, code: :payment_required, data: { status: 402, body: body.to_json, content_type: "application/json" })
    end
  end
end
