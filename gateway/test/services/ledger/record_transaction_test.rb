# frozen_string_literal: true

require "test_helper"

module Ledger
  class RecordTransactionTest < ActiveSupport::TestCase
    test "records the call with a 15% integer commission" do
      req = requirements_for # 5000 µUSDC
      receipt = Payments::Receipt.new(success: true, transaction: "TX9", network: req.network, payer: "PAYER1", error_reason: nil)

      result = RecordTransaction.new(service: service, requirements: req, receipt: receipt, upstream: { status: 200, latency_ms: 812 }).call
      assert result.success?

      call = result[:call].reload
      assert_equal "scrape-markdown", call.service_slug
      assert_equal 5_000, call.amount
      assert_equal 750, call.commission
      assert_equal 4_250, call.seller_amount
      assert_equal "TX9", call.transaction_id
      assert_equal "PAYER1", call.payer_address
      assert_equal 812, call.upstream_latency_ms
      assert_equal "settled", call.status
    end

    test "commission rounds down so the seller gets the remainder" do
      req = requirements_for.with(amount: 7)
      receipt = Payments::Receipt.new(success: true, transaction: "TX10", network: req.network, payer: "P", error_reason: nil)
      call = RecordTransaction.new(service: service, requirements: req, receipt: receipt, upstream: { status: 200, latency_ms: 1 }).call[:call]
      assert_equal 1, call.commission
      assert_equal 6, call.seller_amount
    end
  end
end
