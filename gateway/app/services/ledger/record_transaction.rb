# frozen_string_literal: true

module Ledger
  # Writes one Call row after a settled paid call, splitting the amount into
  # commission (ours) and the seller's share. Integer math only.
  class RecordTransaction
    def initialize(service:, requirements:, receipt:, upstream:, commission_bps: Rails.configuration.x402.commission_bps)
      @service = service
      @requirements = requirements
      @receipt = receipt
      @upstream = upstream
      @commission_bps = commission_bps
    end

    def call
      amount = @requirements.amount
      commission = amount * @commission_bps / 10_000

      call_row = Call.create!(
        service_slug: @service.slug,
        payer_address: @receipt.payer,
        pay_to: @requirements.pay_to,
        network: @requirements.network,
        asset: @requirements.asset,
        amount: amount,
        commission: commission,
        seller_amount: amount - commission,
        transaction_id: @receipt.transaction,
        upstream_status: @upstream[:status],
        upstream_latency_ms: @upstream[:latency_ms],
        status: "settled"
      )
      Result.success(call: call_row)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.message, code: :ledger_error)
    end
  end
end
