# frozen_string_literal: true

require "test_helper"

module Admin
  class WorkOrdersControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

    def job(**attrs)
      WorkOrder.create!({ service_slug: "rfq-global", price_atomic: 250_000_000, status: "pending",
                          brief: "500 units of stainless steel bottles, matte black, logo one side.",
                          params: { "quantity" => "500 units", "destination" => "Port of Houston, TX" } }.merge(attrs))
    end

    test "requires the admin password" do
      get admin_work_orders_url
      assert_response :unauthorized
    end

    test "shows the queue with the brief and what was asked for" do
      pending = job
      job(status: "delivered", delivered_at: Time.current, result: { "quotes" => [] })

      get admin_work_orders_url, headers: auth
      assert_response :success
      assert_select "h2", text: "Queue · 1 pending"
      assert_select "dd", text: "Port of Houston, TX"
      assert_select "form[action='#{admin_deliver_work_order_path(pending.token)}']"
    end

    test "delivering parses the pasted JSON into the result" do
      order = job

      post admin_deliver_work_order_url(order.token), headers: auth,
           params: { result: '{"quotes":[{"supplier":"Acme","unit_price":"4.20"}]}' }

      assert_redirected_to admin_work_orders_path
      order.reload
      assert_equal "delivered", order.status
      assert_equal "Acme", order.result.dig("quotes", 0, "supplier")
      assert order.delivered_at
    end

    test "a hurried paste that is not JSON is kept rather than lost" do
      order = job

      post admin_deliver_work_order_url(order.token), headers: auth, params: { result: "Acme quoted 4.20, 30 days" }

      assert_redirected_to admin_work_orders_path
      assert_equal "Acme quoted 4.20, 30 days", order.reload.result["notes"]
      assert_equal "delivered", order.status
    end

    test "refunding records the transaction that sent the money back" do
      order = job

      post admin_refund_work_order_url(order.token), headers: auth,
           params: { refund_transaction_id: "TXN999", notes: "nobody would quote it" }

      assert_redirected_to admin_work_orders_path
      order.reload
      assert_equal "refunded", order.status
      assert_equal "TXN999", order.refund_transaction_id
      assert_equal "nobody would quote it", order.notes
    end

    private

    def auth
      { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret") }
    end
  end
end
