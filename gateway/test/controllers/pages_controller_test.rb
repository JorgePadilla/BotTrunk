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

  test "llms.txt is rendered from the catalog so prices cannot drift" do
    get "/llms.txt"
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match "scrape-markdown", response.body
    assert_match "$0.09 USDC per call", response.body
    assert_match "$25.00 USDC per call", response.body
    assert_match "npx bottrunk-mcp", response.body
    assert_match "deposit-bac-1000", response.body
    assert_match "Banco Central de Honduras reference rate", response.body
    assert_match "write to hello@bottrunk.com", response.body
    assert_no_match(/pdf-extract/, response.body)
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

  test "sign_in explains agents need no account" do
    get sign_in_url
    assert_response :success
    assert_select "a[href='/docs#connect']"
    assert_select "a[href='/sell#early-access']"
  end

  test "every page carries a description and OpenGraph tags (the Bazaar reads them)" do
    [ root_url, docs_url, sell_url, service_url("scrape-markdown") ].each do |url|
      get url
      assert_select "meta[name=description][content]"
      assert_select "meta[property='og:title'][content]"
      assert_select "meta[property='og:description'][content]"
    end
  end

  test "llms.txt is served" do
    get "/llms.txt"
    assert_response :success
    assert_includes response.body, "/api/v1/catalog"
  end

  test "navbar links resolve" do
    get root_url
    assert_select "nav a[href='/docs']"
    assert_select "nav a[href='/sell']"
    assert_select "a[href='/sign_in']"
    assert_select "a[href='/docs#connect']"
  end
end
