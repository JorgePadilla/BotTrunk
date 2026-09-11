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
    assert_equal "5000", body["accepts"][0]["amount"]
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
    post paid_call_path("pdf-extract"), params: "{}", headers: { "Content-Type" => "application/json", "PAYMENT-SIGNATURE" => payment_header }
    assert_response :success
    assert_equal response.headers["X-PAYMENT-RESPONSE"], response.headers["PAYMENT-RESPONSE"]
    assert_equal "TXID123", JSON.parse(Base64.strict_decode64(response.headers["PAYMENT-RESPONSE"]))["transaction"]
  end

  test "OPTIONS preflight answers with CORS headers" do
    options paid_call_path("pdf-extract"), headers: { "Origin" => "https://example.app" }
    assert_response :no_content
    assert_includes response.headers["Access-Control-Allow-Headers"], "PAYMENT-SIGNATURE"
  end

  test "POST with a valid payment proxies, settles, records and returns X-PAYMENT-RESPONSE" do
    stub_upstream(body: { data: { total: 42 } }.to_json)

    assert_difference("Call.count", 1) do
      post paid_call_path("pdf-extract"), params: { url: "https://example.com/x.pdf" }.to_json,
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

    post paid_call_path("pdf-extract"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }

    assert_response :payment_required
    assert_equal "fake: invalid", response.parsed_body["error"]
    assert_not_requested upstream
  end

  test "upstream failure is 502 and is not settled" do
    stub_upstream(status: 500, body: "boom")
    post paid_call_path("pdf-extract"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }

    assert_response :bad_gateway
    assert_empty @adapter.settle_calls
    assert_equal 0, Call.count
  end

  test "a settled call still returns 200 when the ledger blows up" do
    stub_upstream(body: { ok: true }.to_json)
    Call.singleton_class.alias_method(:create_without_boom!, :create!)
    Call.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "relation calls does not exist" }
    begin
      post paid_call_path("pdf-extract"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    ensure
      Call.singleton_class.alias_method(:create!, :create_without_boom!)
      Call.singleton_class.remove_method(:create_without_boom!)
    end
    assert_response :success
    assert_equal "TXID123", JSON.parse(Base64.strict_decode64(response.headers["X-PAYMENT-RESPONSE"]))["transaction"]
  end

  test "a coming-soon service answers 503 before any payment is looked at" do
    Catalog::Service.treat_all_live = false
    upstream = stub_upstream
    begin
      post paid_call_path("pdf-extract"), params: "{}", headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    ensure
      Catalog::Service.treat_all_live = true
    end

    assert_response :service_unavailable
    assert_equal "coming_soon", response.parsed_body["status"]
    assert_empty @adapter.verify_calls
    assert_not_requested upstream
  end

  test "unknown service is 404" do
    post paid_call_path("nope"), params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :not_found
  end
end
