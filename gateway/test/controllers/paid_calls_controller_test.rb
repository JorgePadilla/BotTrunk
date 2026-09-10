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
    assert body["extensions"]["bazaar"]
    assert_not_requested upstream
    assert_empty @adapter.verify_calls
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

  test "unknown service is 404" do
    post paid_call_path("nope"), params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :not_found
  end
end
