# frozen_string_literal: true

require "test_helper"

# config/initializers/rack_attack.rb. Limits are read from the config rather
# than copied here, so retuning a number does not mean editing the tests.
class RateLimitsTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    # rack-attack counts in fixed windows aligned to the clock. A loop that
    # straddles a minute boundary would start a fresh window halfway through
    # and the request meant to be refused would get through.
    freeze_time
    @adapter = FakePaymentAdapter.new
    Payments::Adapters.stubs_current = @adapter
  end

  teardown { Payments::Adapters.stubs_current = nil }

  def limit(name) = Rails.configuration.x.rate_limits.fetch(name)[:limit]

  def probe = post(paid_call_path("scrape-markdown"), params: "{}", headers: JSON_HEADERS)

  test "unpaid 402 probes are cut off at the limit with a 429 that says nothing was charged" do
    limit(:paywall_probe).times { probe }
    assert_response :payment_required

    probe
    assert_response :too_many_requests
    body = response.parsed_body
    assert_equal false, body["charged"]
    assert_operator body["retry_after"], :>, 0
    assert_equal body["retry_after"].to_s, response.headers["Retry-After"]
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end

  test "a paying agent is not held back by the probe limit" do
    stub_upstream(body: { ok: true }.to_json)
    (limit(:paywall_probe) + 1).times { probe }
    assert_response :too_many_requests

    post paid_call_path("test-proxy"), params: "{}", headers: JSON_HEADERS.merge("PAYMENT-SIGNATURE" => payment_header)
    assert_response :success
  end

  test "payment attempts have their own limit, since each one costs a facilitator round trip" do
    stub_upstream(body: { ok: true }.to_json)
    limit(:paywall_paid).times do
      post paid_call_path("test-proxy"), params: "{}", headers: JSON_HEADERS.merge("X-PAYMENT" => payment_header)
    end
    assert_response :success

    post paid_call_path("test-proxy"), params: "{}", headers: JSON_HEADERS.merge("X-PAYMENT" => payment_header)
    assert_response :too_many_requests
    assert_equal limit(:paywall_paid), @adapter.verify_calls.size
  end

  test "the catalog page and CORS preflights share the path but are never throttled" do
    (limit(:paywall_probe) + 1).times { probe }
    assert_response :too_many_requests

    get service_path("scrape-markdown")
    assert_response :success
    options paid_call_path("scrape-markdown"), headers: { "Origin" => "https://example.app" }
    assert_response :no_content
  end

  test "the hosted MCP endpoint is throttled" do
    rpc = { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json
    limit(:mcp).times { post "/mcp", params: rpc, headers: JSON_HEADERS }
    assert_response :success

    post "/mcp", params: rpc, headers: JSON_HEADERS
    assert_response :too_many_requests
  end

  test "the two public forms share one budget, since each submission sends an email" do
    limit(:forms).times { post seller_inquiries_path, params: { seller_inquiry: { email: "not-an-email" } } }
    assert_response :unprocessable_entity

    assert_no_difference -> { ServiceRequest.count } do
      post service_requests_path, params: { service_request: { email: "buyer@example.com", details: "Valid, but over the limit." } }
    end
    assert_response :too_many_requests
    assert_no_enqueued_emails
  end

  # A refusal outside the app's layout makes Turbo reload /sell, and the person
  # sees nothing happen. They get the page back with what they typed and why.
  test "a person over the form limit sees the form again with their input and the reason" do
    limit(:forms).times { post seller_inquiries_path, params: { seller_inquiry: { email: "not-an-email" } } }

    post seller_inquiries_path, params: { seller_inquiry: { email: "seller@example.com", service_name: "My API" } }
    assert_response :too_many_requests
    assert_equal "text/html", response.media_type
    assert_select "form[action='#{seller_inquiries_path}'] p.text-error", text: /Too many submissions from your network this hour/
    assert_select "input[name='seller_inquiry[email]'][value='seller@example.com']"
  end

  test "each address has its own budget" do
    limit(:paywall_probe).times { probe }
    post paid_call_path("scrape-markdown"), params: "{}", headers: JSON_HEADERS, env: { "REMOTE_ADDR" => "203.0.113.7" }
    assert_response :payment_required
  end
end
