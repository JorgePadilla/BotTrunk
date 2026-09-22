# frozen_string_literal: true

require "test_helper"

class PaidCallsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @adapter = FakePaymentAdapter.new
    Payments::Adapters.stubs_current = @adapter
  end

  teardown { Payments::Adapters.stubs_current = nil }

  test "POST without X-PAYMENT answers 402 with requirements and no upstream call" do
    upstream = stub_upstream
    post paid_call_path("scrape-markdown"), params: { url: "https://example.com" }.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :payment_required
    body = response.parsed_body
    assert_equal 2, body["x402Version"]
    assert_equal "90000", body["accepts"][0]["amount"]
    assert_equal TEST_PAY_TO, body["accepts"][0]["payTo"]
    assert_equal "x402-global-challenge", body["accepts"][0]["extra"]["tag"]
    assert body["extensions"]["bazaar"]["schema"]
    assert_equal body, JSON.parse(Base64.strict_decode64(response.headers["PAYMENT-REQUIRED"]))
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Access-Control-Expose-Headers"], "PAYMENT-REQUIRED"
    assert_not_requested upstream
    assert_empty @adapter.verify_calls
  end

  test "PAYMENT-SIGNATURE (x402 v2 header) is accepted and PAYMENT-RESPONSE is returned" do
    stub_upstream(body: { ok: true }.to_json)
    post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "PAYMENT-SIGNATURE" => payment_header }
    assert_response :success
    assert_equal response.headers["X-PAYMENT-RESPONSE"], response.headers["PAYMENT-RESPONSE"]
    assert_equal "TXID123", JSON.parse(Base64.strict_decode64(response.headers["PAYMENT-RESPONSE"]))["transaction"]
  end

  test "OPTIONS preflight answers with CORS headers" do
    options paid_call_path("test-proxy"), headers: { "Origin" => "https://example.app" }
    assert_response :no_content
    assert_includes response.headers["Access-Control-Allow-Headers"], "PAYMENT-SIGNATURE"
  end

  test "POST with a valid payment proxies, settles, records and returns X-PAYMENT-RESPONSE" do
    stub_upstream(body: { data: { total: 42 } }.to_json)

    assert_difference("Call.count", 1) do
      post paid_call_path("test-proxy"), params: { url: "https://example.com/x.pdf" }.to_json,
           headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    end

    assert_response :success
    assert_equal 42, response.parsed_body.dig("data", "total")
    receipt = JSON.parse(Base64.strict_decode64(response.headers["X-PAYMENT-RESPONSE"]))
    assert_equal "TXID123", receipt["transaction"]
    assert_equal 1, @adapter.verify_calls.size
    assert_equal 1, @adapter.settle_calls.size
    assert_equal "TXID123", Call.last.transaction_id
  end

  test "invalid payment is 402 and never reaches upstream or settle" do
    Payments::Adapters.stubs_current = FakePaymentAdapter.new(valid: false)
    upstream = stub_upstream

    post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }

    assert_response :payment_required
    assert_equal "fake: invalid", response.parsed_body["error"]
    assert_not_requested upstream
  end

  test "upstream failure is 502 and is not settled" do
    stub_upstream(status: 500, body: "boom")
    post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }

    assert_response :bad_gateway
    assert_empty @adapter.settle_calls
    assert_equal 0, Call.count
  end

  test "a settled call still returns 200 when the ledger blows up" do
    stub_upstream(body: { ok: true }.to_json)
    Call.singleton_class.alias_method(:create_without_boom!, :create!)
    Call.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "relation calls does not exist" }
    begin
      post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    ensure
      Call.singleton_class.alias_method(:create!, :create_without_boom!)
      Call.singleton_class.remove_method(:create_without_boom!)
    end
    assert_response :success
    assert_equal "TXID123", JSON.parse(Base64.strict_decode64(response.headers["X-PAYMENT-RESPONSE"]))["transaction"]
  end

  test "a service that is not live answers 503 before any payment is looked at" do
    Catalog::Service.treat_all_live = false
    upstream = stub_upstream
    begin
      post paid_call_path("test-on-request"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    ensure
      Catalog::Service.treat_all_live = true
    end

    assert_response :service_unavailable
    assert_equal "on_request", response.parsed_body["status"]
    assert_equal "coming_soon", Event.last.name

    # The 503 has to be a way in, not a dead end: an agent that lands here
    # should learn it was not charged and how the service is arranged.
    body = response.parsed_body
    assert_equal false, body["charged"]
    assert_equal "human_fulfilled_arrange_first", body["reason"]
    assert_match "hello@bottrunk.com", body["how_to_arrange"]
    assert_match "fulfilled by a person", body["error"]
    assert_empty @adapter.verify_calls
    assert_not_requested upstream
  end

  test "a 402 probe and a rejected payment are recorded as events, a settled call is not" do
    stub_upstream(body: { ok: true }.to_json)

    post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "User-Agent" => "bottrunk-mcp/0.1.0" }
    assert_equal [ "payment_required" ], Event.pluck(:name)
    assert_equal "bottrunk-mcp", Event.last.client
    assert_equal "test-proxy", Event.last.service_slug

    Payments::Adapters.stubs_current = FakePaymentAdapter.new(valid: false)
    post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    assert_equal "payment_rejected", Event.last.name
    assert_equal "fake: invalid", Event.last.properties["reason"]

    Payments::Adapters.stubs_current = @adapter
    assert_no_difference("Event.count") do
      post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    end
    assert_response :success
  end

  test "a 4xx from the service is passed through and never charged" do
    stub_upstream(status: 422, body: { error: "bad url" }.to_json)
    post paid_call_path("test-proxy"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }

    assert_response :unprocessable_entity
    assert_equal "bad url", response.parsed_body["error"]
    assert_empty @adapter.settle_calls
    assert_nil response.headers["X-PAYMENT-RESPONSE"]
    assert_equal 0, Call.count
  end

  test "a lempira deposit opens an order, settles the quoted USDC and queues the order" do
    input = { beneficiary_name: "María Pérez", account_number: "123456789", concept: "Factura 7" }.to_json

    post paid_call_path("deposit-bac-1000"), params: input, headers: { "Content-Type" => "application/json" }
    assert_response :payment_required
    assert_equal "42510122", response.parsed_body.dig("accepts", 0, "amount")
    assert_equal 0, DepositOrder.count, "no order before a payment is presented"

    post paid_call_path("deposit-bac-1000"), params: input, headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    assert_response :accepted
    body = response.parsed_body
    assert_equal "pending", body["status"]
    assert_equal 1000, body["amount_hnl"]

    order = DepositOrder.find_by!(token: body["order_id"])
    assert_equal "pending", order.status
    assert_equal Call.last, order.call
    assert_equal 42_510_122, Call.last.amount
    assert_equal 1, @adapter.settle_calls.size

    get order_path(order.token)
    assert_response :success
    assert_equal "pending", response.parsed_body["status"]
    assert_nil response.parsed_body["account_number"]
  end

  test "a deposit with bad input is refused before any money moves" do
    post paid_call_path("deposit-bac-1000"), params: { beneficiary_name: "X", account_number: "12" }.to_json,
         headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    assert_response :unprocessable_entity
    assert_empty @adapter.settle_calls
    assert_equal 0, DepositOrder.count
  end

  test "a deposit whose settlement fails is cancelled, not queued" do
    Payments::Adapters.stubs_current = FakePaymentAdapter.new(settle_success: false)
    post paid_call_path("deposit-bac-1000"), params: { beneficiary_name: "María", account_number: "123456789" }.to_json,
         headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    assert_response :payment_required
    assert_equal [ "cancelled" ], DepositOrder.pluck(:status)
  end

  test "unknown service is 404" do
    post paid_call_path("nope"), params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :not_found
  end
end
