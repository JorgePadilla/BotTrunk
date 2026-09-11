# frozen_string_literal: true

# In-memory adapter for tests: no HTTP, fully scriptable.
class FakePaymentAdapter < Payments::Adapters::Base
  attr_reader :verify_calls, :settle_calls

  def initialize(valid: true, payer: "PAYERADDRESS", settle_success: true, transaction: "TXID123")
    @valid = valid
    @payer = payer
    @settle_success = settle_success
    @transaction = transaction
    @verify_calls = []
    @settle_calls = []
  end

  def verify(payload:, requirements:, extensions: nil)
    @verify_calls << [ payload, requirements ]
    @valid ? Result.success(payer: @payer) : Result.failure("fake: invalid", code: :invalid_payment)
  end

  def settle(payload:, requirements:, extensions: nil)
    @settle_calls << [ payload, requirements ]
    receipt = Payments::Receipt.new(success: @settle_success, transaction: @settle_success ? @transaction : nil,
                                    network: requirements.network, payer: @payer, error_reason: @settle_success ? nil : "fake: settle failed")
    @settle_success ? Result.success(receipt: receipt) : Result.failure(receipt.error_reason, code: :settlement_failed, data: { receipt: receipt })
  end
end
