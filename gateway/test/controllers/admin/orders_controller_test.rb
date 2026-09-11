# frozen_string_literal: true

require "test_helper"

module Admin
  class OrdersControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

    def order(**attrs)
      DepositOrder.create!({ service_slug: "deposit-bac-1000", amount_hnl: 1000, price_atomic: 42_510_122, rate_hnl_per_usd: 24.7, fee_bps: 500,
                             beneficiary_name: "María Pérez", account_number: "123456789", status: "pending" }.merge(attrs))
    end

    test "requires the admin password" do
      get admin_orders_url
      assert_response :unauthorized
    end

    test "shows the queue with bank details and the done list without them" do
      pending = order
      done = order(status: "delivered", receipt_reference: "88231", delivered_at: Time.current, beneficiary_name: "Juan Díaz")
      order(status: "cancelled", beneficiary_name: "Ghost")

      get admin_orders_url, headers: auth
      assert_response :success
      assert_select "h2", text: "Queue · 1 pending"
      assert_select "dd", text: "123456789"
      assert_select "form[action='#{admin_deliver_order_path(pending.token)}']"
      assert_select "td", text: "Juan Díaz"
      assert_select "td", text: "88231"
      assert_select "td", text: "Ghost"
      assert_select "a", text: /Orders · 1 pending/
    end

    test "marks an order delivered with the receipt reference" do
      o = order
      post admin_deliver_order_url(o.token), params: { receipt_reference: "BAC-1001" }, headers: auth
      assert_redirected_to admin_orders_path
      assert_equal "delivered", o.reload.status
      assert_equal "BAC-1001", o.receipt_reference

      get order_url(o.token)
      assert_equal "delivered", response.parsed_body["status"]
      assert_equal "BAC-1001", response.parsed_body["receipt_reference"]
    end

    test "marks an order refunded with the refund transaction" do
      o = order
      post admin_refund_order_url(o.token), params: { refund_transaction_id: "REFUNDTXN", notes: "bank rejected" }, headers: auth
      assert_redirected_to admin_orders_path
      assert_equal "refunded", o.reload.status
      assert_equal "REFUNDTXN", o.refund_transaction_id
    end

    test "unknown order status is 404" do
      get order_url("nope")
      assert_response :not_found
    end

    private

    def auth
      { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret") }
    end
  end
end
