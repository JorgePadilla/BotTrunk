# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "docs shows the real 402 for the example service" do
    get docs_url
    assert_response :success
    assert_select "h1", text: "Pay per call. Nothing else."
    assert_select "section#connect"
    assert_includes response.body, "x402-global-challenge"
    assert_includes response.body, TEST_PAY_TO
    assert_includes response.body, "/api/v1/catalog"
  end

  test "connect lists every client with its own snippet" do
    get connect_url
    assert_response :success
    assert_select "h1", text: "Connect your agent"
    # Scoped to the client list on purpose: counting every h3 on the page made
    # this fail the day /connect grew two subheadings that are not clients.
    assert_select "#clients h3", count: Docs::McpClient.all.size
    assert_select "section#openclaw h3", text: "OpenClaw"
    assert_select "section#hermes h3", text: "Hermes Agent"
    assert_match "openclaw mcp add bottrunk", response.body
    assert_match "mcp_servers:", response.body
    assert_match "context_servers", response.body          # Zed
    assert_match "&quot;servers&quot;", response.body      # VS Code, not mcpServers
    assert_match "MCPServerStdio", response.body
    assert_match "npx bottrunk-mcp wallet", response.body
    assert_select "a[href='https://docs.openclaw.ai/tools/mcp']"
    assert_select "span.font-mono", text: "--scope user", message: "backticks in the notes render as code"
  end

  test "connect suggests the per-call cap bottrunk-mcp defaults to" do
    get connect_url
    assert_match "&quot;BOTTRUNK_MAX_PER_CALL&quot;: &quot;10000&quot;", response.body
    assert_match "BOTTRUNK_MAX_PER_CALL: &quot;10000&quot;", response.body   # Hermes
    assert_no_match(/BOTTRUNK_MAX_PER_CALL(&quot;)?: &quot;0\.50/, response.body)
  end

  test "llms.txt is rendered from the catalog so prices cannot drift" do
    get "/llms.txt"
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match "scrape-markdown", response.body
    assert_match "$0.09 USDC per call", response.body
    assert_match "$45.00 USDC per call", response.body
    assert_match "npx bottrunk-mcp", response.body
    assert_match "deposit-bac-1000", response.body
    assert_match "Banco Central de Honduras reference rate", response.body
    assert_match "write to hello@bottrunk.com", response.body
    assert_no_match(/pdf-extract/, response.body)
  end

  test "llms.txt states the wallet needs ALGO once, and does not advertise a TestNet we do not serve" do
    get "/llms.txt"

    assert_match "0.3 ALGO once", response.body
    assert_match "cannot pay at all", response.body
    assert_match "MainNet** only", response.body
    assert_no_match(/10458941/, response.body)
  end

  test "llms.txt publishes the error contract and the retry hazard" do
    get "/llms.txt"

    assert_match "settlement failed", response.body
    assert_match "pays twice", response.body
    assert_match "selector", response.body
    assert_match "PAYMENT-REQUIRED", response.body
  end

  test "no page links to the private repository" do
    [ root_path, docs_path, connect_path, sell_path ].each do |path|
      get path
      assert_no_match(/github\.com\/JorgePadilla/, response.body, path)
    end
  end

  test "docs still renders when no payTo is configured" do
    original = Rails.configuration.x402.pay_to
    Rails.configuration.x402.pay_to = nil
    get docs_url
    assert_response :success
    assert_includes response.body, "PAYTO…"
  ensure
    Rails.configuration.x402.pay_to = original
  end

  test "sell shows the early-access form" do
    get sell_url
    assert_response :success
    assert_select "form[action='/sell']"
    assert_select "input[name='seller_inquiry[email]']"
    assert_select "input[name='seller_inquiry[price_usdc]']"
  end

  test "sell shows a confirmation after submitting" do
    get sell_url(submitted: 1)
    assert_response :success
    assert_select "form[action='/sell']", count: 0
    assert_select "h2", text: "Got it."
  end

  test "sell asks the other question too: what are we missing" do
    get sell_url
    assert_response :success
    assert_select "form[action='/service-requests']"
    assert_select "input[name='service_request[email]']"
    assert_select "textarea[name='service_request[details]']"
  end

  test "the request form offers the catalog, and 'something you don't list yet' first" do
    get sell_url

    assert_select "select[name='service_request[service_slug]'] option[value='']", text: /don't list yet/
    assert_select "select[name='service_request[service_slug]'] option[value='scrape-markdown']"
  end

  test "sell confirms a request without pretending the seller form was sent" do
    get sell_url(requested: 1)
    assert_response :success
    assert_select "form[action='/service-requests']", count: 0
    assert_select "form[action='/sell']", 1, "the seller form must still be there"
  end

  test "sign_in explains agents need no account" do
    get sign_in_url
    assert_response :success
    assert_select "a[href='/connect']"
    assert_select "a[href='/sell#early-access']"
  end

  test "every page carries a description and OpenGraph tags (the Bazaar reads them)" do
    [ root_url, docs_url, connect_url, sell_url, service_url("scrape-markdown") ].each do |url|
      get url
      assert_select "meta[name=description][content]"
      assert_select "meta[property='og:title'][content]"
      assert_select "meta[property='og:description'][content]"
    end
  end

  test "navbar links resolve" do
    get root_url
    assert_select "nav a[href='/docs']"
    assert_select "nav a[href='/sell']"
    assert_select "nav a[href='/connect']"
    assert_select "a[href='/connect']", text: "Connect agent"
    assert_select "a[href='/sign_in']", count: 0, message: "there are no accounts, so no dead Sign in"
  end
end
