# frozen_string_literal: true

require "test_helper"

# The facilitator probes these paths and treats an HTML body as "file absent",
# so every one of them has to answer 200 with real, parseable content. The
# price assertions matter more than they look: the Bazaar listing for
# scrape-markdown froze at an old price because nothing tied the published
# numbers to the ones the endpoint charges.
class WellKnownControllerTest < ActionDispatch::IntegrationTest
  test "x402 index publishes every live endpoint at the price its 402 quotes" do
    get "/.well-known/x402"
    assert_response :success
    assert_equal "application/json", response.media_type

    body = JSON.parse(response.body)
    assert_equal 2, body["x402Version"]

    live = Catalog::Service.all.select(&:live?)
    assert_equal live.map(&:endpoint_url).sort, body["resources"].map { |r| r["url"] }.sort

    body["resources"].each do |resource|
      service = Catalog::Service.all.find { |s| s.endpoint_url == resource["url"] }
      assert_equal service.price_atomic.to_s, resource["amount"],
                   "#{service.slug} is published at a price its endpoint does not charge"
      assert_equal TEST_PAY_TO, resource["payTo"]
      assert_equal "POST", resource["method"]
    end
  end

  # The suite runs with `treat_all_live = true` so the paid-call tests can drive
  # services the seed lists as on_request. That makes `live?` true for
  # everything, which is the opposite of what this test is about — so it asks
  # the question with the flag off, the way production answers it.
  test "an on_request service is never published as payable" do
    on_request = nil
    with_real_statuses do
      on_request = Catalog::Service.all.select(&:on_request?)
      skip "no on_request services in the catalog" if on_request.empty?
      get "/.well-known/x402"
    end

    urls = JSON.parse(response.body)["resources"].map { |r| r["url"] }
    assert_not_empty urls, "the live services should still be published"
    on_request.each { |service| assert_not_includes urls, service.endpoint_url }
  end

  def with_real_statuses
    Catalog::Service.treat_all_live = false
    yield
  ensure
    Catalog::Service.treat_all_live = true
  end

  test "agent card, manifest and mcp manifest are JSON with a name and description" do
    {
      "/.well-known/agent-card.json" => "skills",
      "/.well-known/agent.json" => "payments",
      "/.well-known/mcp.json" => "tools"
    }.each do |path, required_key|
      get path
      assert_response :success, "#{path} must answer 200 or the facilitator counts it absent"
      assert_equal "application/json", response.media_type, "#{path} must not be HTML"

      body = JSON.parse(response.body)
      assert body["name"].present?, "#{path} has no name"
      assert body["description"].present?, "#{path} has no description"
      assert body[required_key].present?, "#{path} has no #{required_key}"
    end
  end

  test "mcp manifest points at the hosted Streamable HTTP endpoint" do
    get "/.well-known/mcp.json"
    transport = JSON.parse(response.body)["transport"]
    assert_equal "streamable-http", transport["type"]
    assert_equal "https://mcp.bottrunk.com/mcp", transport["url"]
  end

  test "agents.md is markdown that names the endpoints and their prices" do
    get "/agents.md"
    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_match(/\A# BotTrunk/, response.body)

    live = Catalog::Service.all.select(&:live?)
    live.each { |service| assert_includes response.body, "/s/#{service.slug}" }
    assert_includes response.body, "PAYMENT-SIGNATURE"
  end
end
