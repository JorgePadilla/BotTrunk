# frozen_string_literal: true

require "test_helper"

module Admin
  class StatsControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

    test "bare /admin redirects to the dashboard, which still asks for auth" do
      get "/admin"
      assert_response :found
      assert_redirected_to "/admin/stats"

      # The redirect is a routing-layer endpoint, so it never reaches
      # Admin::BaseController. Nothing is exposed: the target still challenges.
      follow_redirect!
      assert_response :unauthorized
    end

    test "asks for basic auth and refuses a wrong password" do
      get admin_stats_url
      assert_response :unauthorized

      get admin_stats_url, headers: basic("admin", "nope")
      assert_response :unauthorized
    end

    test "refuses everything when no password is configured" do
      ENV.delete("ADMIN_PASSWORD")
      get admin_stats_url, headers: basic("admin", "")
      assert_response :unauthorized
    end

    test "renders the dashboard with events and calls" do
      Analytics::Track.new(name: "page_view", path: "/docs", referrer: "https://news.ycombinator.com/", user_agent: "Mozilla/5.0", ip: "1.2.3.4").call
      Analytics::Track.new(name: "payment_required", service_slug: "scrape-markdown", user_agent: "bottrunk-mcp/0.1.0", properties: { reason: "Payment required" }).call
      Call.create!(service_slug: "scrape-markdown", pay_to: "G", network: "n", asset: "a", amount: 5000, commission: 750, seller_amount: 4250,
                   payer_address: "LQAWG3WUMKWTFGEFCCOET6JGPRKD2JFYPIJ6HPIRYAC6QDUJSBDVMCKPFQ", transaction_id: "JJZEUY73ABCD", status: "settled")

      get admin_stats_url(days: 7), headers: basic("admin", "s3cret")
      assert_response :success
      assert_select "h1", "What is happening"
      assert_select "dd", text: "$0.005"
      assert_select "td", text: "news.ycombinator.com"
      assert_select "td", text: "bottrunk-mcp"
      assert_select "a[href='https://allo.info/tx/JJZEUY73ABCD']"
      assert_select "svg[role=img]", 3
      assert_select "h2", text: "Countries"
      assert_select "p", text: /No GeoIP database/
    end

    test "shows countries by name when events are located" do
      Analytics::Geolocate.stubs_lookup = ->(_ip) { { country: "HN", city: "Tegucigalpa, Francisco Morazán" } }
      Analytics::Track.new(name: "page_view", path: "/", ip: "190.4.0.1", user_agent: "Mozilla/5.0").call
      get admin_stats_url, headers: basic("admin", "s3cret")
      assert_select "td", text: "Honduras (HN)"
      assert_select "td", text: "Tegucigalpa, Francisco Morazán"
    ensure
      Analytics::Geolocate.stubs_lookup = nil
    end

    test "shows the lempira rate, tier prices and history, and can refresh it" do
      ExchangeRate.create!(source: "bch", rate: 26.1834, as_of: Date.new(2026, 9, 11), fetched_at: Time.current)
      get admin_stats_url, headers: basic("admin", "s3cret")
      assert_response :success
      assert_select "h2", text: "Lempira rate"
      assert_select "dd", text: "L26.2"       # the pinned test rate, printed as stored
      assert_select "dd", text: "L24.7"       # after the L1.50 spread, as to_s("F") prints it
      assert_select "dd", text: "$42.51"
      assert_select "td", text: "deposit-bac-10000"
      assert_select "td", text: "$425.10"
      assert_select "td", text: "L26.1834"
      assert_select "form[action='#{admin_refresh_rates_path}']"

      Rates::UsdHnl.stub_rate = nil
      stub_request(:get, Rates::UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.40 } }.to_json, headers: { "Content-Type" => "application/json" })
      post admin_refresh_rates_url, headers: basic("admin", "s3cret")
      assert_redirected_to admin_stats_path(anchor: "rates")
      assert_equal BigDecimal("26.40"), ExchangeRate.newest_first.first.rate
    ensure
      Rates::UsdHnl.stub_rate = "26.20"
    end

    test "days is clamped to 7..90" do
      get admin_stats_url(days: 1000), headers: basic("admin", "s3cret")
      assert_response :success
      assert_select "a.btn:not(.btn-ghost)", text: "90 days"
    end

    private

    def basic(user, password)
      { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
    end
  end
end
