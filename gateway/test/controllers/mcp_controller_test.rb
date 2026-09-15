# frozen_string_literal: true

require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  def rpc(method, params = {}, id: 1)
    body = { jsonrpc: "2.0", method: method, params: params }
    body[:id] = id unless id.nil?
    post "/mcp", params: body.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2026-07-28" }
    response.parsed_body
  end

  test "initialize answers with the client's protocol version, tool capability and instructions" do
    result = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "probe", version: "1" } })["result"]

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "2025-06-18", result["protocolVersion"]
    assert_equal({ "listChanged" => false }, result["capabilities"]["tools"])
    assert_equal "bottrunk", result["serverInfo"]["name"]
    assert_match "cannot spend money for you", result["instructions"]
  end

  test "an unknown protocol version falls back to the newest we speak" do
    assert_equal Mcp::Dispatch::LATEST_VERSION, rpc("initialize", { protocolVersion: "1999-01-01" })["result"]["protocolVersion"]
  end

  test "a notification is accepted with no body" do
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :accepted
    assert_empty response.body
  end

  test "tools/list advertises every free tool with a schema" do
    tools = rpc("tools/list")["result"]["tools"]
    assert_equal %w[bottrunk_catalog bottrunk_order_status bottrunk_payment_instructions bottrunk_quote_deposit bottrunk_service], tools.map { |t| t["name"] }.sort
    tools.each do |tool|
      assert tool["description"].present?
      assert_equal "object", tool["inputSchema"]["type"]
    end
  end

  test "the catalog tool lists services with live prices and filters" do
    payload = JSON.parse(rpc("tools/call", { name: "bottrunk_catalog", arguments: {} })["result"]["content"][0]["text"])
    slugs = payload["services"].map { |s| s["slug"] }
    assert_includes slugs, "scrape-markdown"
    assert_includes slugs, "deposit-bac-1000"
    assert_equal "0.090000", payload["services"].find { |s| s["slug"] == "scrape-markdown" }["price_usdc"]

    filtered = JSON.parse(rpc("tools/call", { name: "bottrunk_catalog", arguments: { category: "payments" } })["result"]["content"][0]["text"])
    assert filtered["services"].all? { |s| s["slug"].start_with?("deposit-bac") }
  end

  test "the service tool returns schema, an example body and how to pay" do
    payload = JSON.parse(rpc("tools/call", { name: "bottrunk_service", arguments: { slug: "page-metadata" } })["result"]["content"][0]["text"])
    assert_equal "Page metadata", payload["name"]
    assert_equal "url", payload["inputs"][0]["name"]
    assert_equal "https://stripe.com", payload["example_request"]["body"]["url"]
    assert_match "bottrunk_page_metadata", payload["how_to_pay"]
  end

  test "payment instructions carry the real x402 requirements" do
    payload = JSON.parse(rpc("tools/call", { name: "bottrunk_payment_instructions", arguments: { slug: "scrape-markdown" } })["result"]["content"][0]["text"])
    assert_equal "90000", payload["payment_requirements"]["amount"]
    assert_equal TEST_PAY_TO, payload["payment_requirements"]["payTo"]
    assert_equal "x402-global-challenge", payload["payment_requirements"]["extra"]["tag"]
    assert_equal 5, payload["steps"].size
    assert_match "npx bottrunk-mcp", payload["easier"]
    # A bot with only this tool has to be able to build the header from it.
    assert_equal 2, payload["payload_shape"]["x402Version"]
    assert_includes payload["payload_shape"]["payload"].keys, "paymentGroup"
    assert_match "inside `accepted`", payload["payload_note"]
  end

  test "an on-request service explains itself instead of quoting a payment" do
    Catalog::Service.treat_all_live = false
    begin
      result = rpc("tools/call", { name: "bottrunk_payment_instructions", arguments: { slug: "verify-business-hn" } })["result"]
    ensure
      Catalog::Service.treat_all_live = true
    end
    assert result["isError"]
    assert_match "hello@bottrunk.com", result["content"][0]["text"]
  end

  test "the deposit quote breaks down rate, spread and fee" do
    payload = JSON.parse(rpc("tools/call", { name: "bottrunk_quote_deposit", arguments: { amount_hnl: 1000 } })["result"]["content"][0]["text"])
    assert_equal "42.510122", payload["price_usdc"]
    assert_equal "26.2", payload["rate"]["reference"]
    assert_equal "24.7", payload["rate"]["buyer_rate"]
    assert_equal 5.0, payload["rate"]["fee_percent"]

    odd = rpc("tools/call", { name: "bottrunk_quote_deposit", arguments: { amount_hnl: 3333 } })["result"]
    assert odd["isError"]
    assert_match "fixed amounts", odd["content"][0]["text"]
  end

  test "order status is readable by token and says nothing about the bank account" do
    order = DepositOrder.create!(service_slug: "deposit-bac-1000", amount_hnl: 1000, price_atomic: 42_510_122, rate_hnl_per_usd: 24.7,
                                 fee_bps: 500, beneficiary_name: "María Pérez", account_number: "123456789", status: "pending")
    payload = JSON.parse(rpc("tools/call", { name: "bottrunk_order_status", arguments: { order_id: order.token } })["result"]["content"][0]["text"])
    assert_equal "pending", payload["status"]
    assert_equal 1000, payload["amount_hnl"]
    assert_nil payload["account_number"]

    assert rpc("tools/call", { name: "bottrunk_order_status", arguments: { order_id: "nope" } })["result"]["isError"]
  end

  test "an unknown tool and an unknown method are errors, not crashes" do
    assert rpc("tools/call", { name: "bottrunk_transfer_everything", arguments: {} })["result"]["isError"]

    error = rpc("resources/list")["error"]
    assert_equal Mcp::Dispatch::METHOD_NOT_FOUND, error["code"]
    assert_match "tools only", error["message"]
  end

  test "tool calls are recorded so /admin/stats sees MCP traffic" do
    assert_difference("Event.where(name: 'mcp_call').count", 1) do
      rpc("tools/call", { name: "bottrunk_catalog", arguments: {} })
    end
    assert_equal "bottrunk_catalog", Event.last.service_slug
  end

  test "malformed JSON and batches are refused politely" do
    post "/mcp", params: "not json", headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
    assert_equal Mcp::Dispatch::PARSE_ERROR, response.parsed_body["error"]["code"]

    post "/mcp", params: [ { jsonrpc: "2.0", id: 1, method: "ping" } ].to_json, headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
    assert_match "one JSON-RPC message", response.parsed_body["error"]["message"]
  end

  test "GET and DELETE say the endpoint is POST-only; OPTIONS passes CORS" do
    get "/mcp"
    assert_response :method_not_allowed
    assert_equal "POST, OPTIONS", response.headers["Allow"]

    delete "/mcp"
    assert_response :method_not_allowed

    process(:options, "/mcp", as: :json)
    assert_response :no_content
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end

  test "ping is answered" do
    assert_equal({}, rpc("ping")["result"])
  end
end
