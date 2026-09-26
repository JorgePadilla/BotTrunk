# frozen_string_literal: true

require "test_helper"

class WorkOrderTest < ActiveSupport::TestCase
  def build(**attrs)
    WorkOrder.create!({ service_slug: "rfq-global", price_atomic: 250_000_000,
                        brief: "500 units of stainless steel bottles, logo on one side." }.merge(attrs))
  end

  test "gets a token and tells a polling agent nothing it has not earned yet" do
    order = build(status: "pending")

    assert_match(/\A[1-9A-HJ-NP-Za-km-z]{20}\z/, order.token)
    status = order.public_status
    assert_equal order.token, status[:order_id]
    assert_equal "pending", status[:status]
    assert_equal "within 5 business days", status[:eta]
    assert_equal "250.0", status[:paid_usdc]
    assert_nil status[:result], "the result is withheld until it exists"
  end

  test "deliver! records the work and releases the result" do
    order = build(status: "pending")
    assert_includes WorkOrder.queue, order

    order.deliver!(result: { "quotes" => [ { "supplier" => "Acme", "unit_price" => "4.20" } ] })

    assert_equal "delivered", order.status
    assert order.delivered_at
    assert_equal "Acme", order.public_status[:result]["quotes"].first["supplier"]
    assert_nil order.public_status[:eta], "a delivered job has no waiting left"
    assert_includes WorkOrder.done, order
    assert_not_includes WorkOrder.queue, order
  end

  test "refund! records the transaction that returned the money" do
    order = build(status: "pending")
    order.refund!(transaction_id: "  TXN123  ", notes: "nobody would quote that spec")

    assert_equal "refunded", order.status
    assert_equal "TXN123", order.refund_transaction_id
    assert_equal "TXN123", order.public_status[:refund_transaction_id]
    assert order.refunded_at
    assert_includes WorkOrder.done, order
  end

  test "a job needs a brief and a price that is really a price" do
    assert_raises(ActiveRecord::RecordInvalid) { build(brief: "") }
    assert_raises(ActiveRecord::RecordInvalid) { build(price_atomic: 0) }
    assert_raises(ActiveRecord::RecordInvalid) { build(status: "invented") }
  end

  test "OrderLookup finds either kind of order by token, and nothing else" do
    work = build(status: "pending")
    deposit = DepositOrder.create!(service_slug: "deposit-bac-1000", amount_hnl: 1000, price_atomic: 42_510_122,
                                   rate_hnl_per_usd: 24.7, fee_bps: 500, beneficiary_name: "Ana", account_number: "123456")

    assert_equal work, OrderLookup.find(work.token)
    assert_equal deposit, OrderLookup.find(deposit.token)
    assert_nil OrderLookup.find("nope")
    assert_nil OrderLookup.find(nil)
    assert_nil OrderLookup.find("  ")
  end
end
