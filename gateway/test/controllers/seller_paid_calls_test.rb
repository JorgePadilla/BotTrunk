# frozen_string_literal: true

require "test_helper"

# A paid call to an outside seller's API, through the real endpoint.
class SellerPaidCallsTest < ActionDispatch::IntegrationTest
  setup do
    @adapter = FakePaymentAdapter.new
    Payments::Adapters.stubs_current = @adapter
    @listing = live_listing
  end

  teardown { Payments::Adapters.stubs_current = nil }

  def pay(body = { number: "08019995" }.to_json)
    post paid_call_path("company-lookup"), params: body, headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
  end

  test "the 402 quotes the seller's price" do
    post paid_call_path("company-lookup"), params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :payment_required
    assert_equal "50000", response.parsed_body["accepts"][0]["amount"]
  end

  test "a paid call is forwarded signed, settled, and recorded against the seller" do
    body = { number: "08019995" }.to_json
    upstream = stub_request(:post, "https://api.seller.example/lookup").with { |req|
      ts = req.headers["Bottrunk-Timestamp"]
      req.body == body && req.headers["Bottrunk-Service"] == "company-lookup" &&
        req.headers["Bottrunk-Signature"] == "v1=#{Gateway::ProxyCall.signature(@listing.seller.signing_secret, ts, body)}"
    }.to_return(status: 200, body: { name: "ACME S. de R.L." }.to_json, headers: { "Content-Type" => "application/json" })

    assert_difference("Call.count", 1) { pay(body) }

    assert_response :success
    assert_equal "ACME S. de R.L.", response.parsed_body["name"]
    assert_requested upstream
    call = Call.last
    assert_equal @listing.seller_id, call.seller_id
    assert_equal 42_500, call.seller_amount
  end

  test "an upstream that now resolves privately is refused before anything leaves, and nothing is charged" do
    @listing.update_columns(upstream_url: "https://db.internal/lookup")
    Current.listing_services = nil

    pay
    assert_response :bad_gateway
    assert_empty @adapter.settle_calls
    assert_not_requested :post, "https://db.internal/lookup"
  end

  test "a built-in call records no seller" do
    stub_request(:get, "https://example.com/").to_return(status: 200, body: "<html><head><title>Hi</title></head></html>", headers: { "Content-Type" => "text/html" })
    post paid_call_path("page-metadata"), params: { url: "https://example.com/" }.to_json, headers: { "Content-Type" => "application/json", "X-PAYMENT" => payment_header }
    assert_response :success
    assert_nil Call.last.seller_id
  end
end
