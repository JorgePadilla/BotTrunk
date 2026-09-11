# frozen_string_literal: true

require "test_helper"

class DepositOrderTest < ActiveSupport::TestCase
  def build(**attrs)
    DepositOrder.create!({ service_slug: "deposit-bac-1000", amount_hnl: 1000, price_atomic: 42_510_122, rate_hnl_per_usd: 24.7, fee_bps: 500,
                           beneficiary_name: "Ana", account_number: "123456" }.merge(attrs))
  end

  test "gets a token, encrypts the account number and exposes no bank details publicly" do
    order = build
    assert_match(/\A[1-9A-HJ-NP-Za-km-z]{20}\z/, order.token)
    raw = DepositOrder.connection.select_value("SELECT account_number FROM deposit_orders WHERE id = #{order.id}")
    assert_not_equal "123456", raw
    assert_equal "123456", order.reload.account_number
    assert_nil order.public_status[:account_number]
    assert_equal BigDecimal("42.510122"), BigDecimal(order.public_status[:paid_usdc])
  end

  test "deliver! and refund! move through the lifecycle" do
    order = build(status: "pending")
    assert_includes DepositOrder.queue, order
    order.deliver!(receipt_reference: " 88231 ")
    assert_equal "delivered", order.status
    assert_equal "88231", order.receipt_reference
    assert order.delivered_at
    assert_includes DepositOrder.done, order
    assert_not_includes DepositOrder.queue, order

    other = build(status: "pending")
    other.refund!(transaction_id: "TXN", notes: "bank rejected")
    assert_equal "refunded", other.status
    assert_equal "bank rejected", other.notes
  end
end
