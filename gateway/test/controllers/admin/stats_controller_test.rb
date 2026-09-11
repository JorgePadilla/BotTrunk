# frozen_string_literal: true

require "test_helper"

module Admin
  class StatsControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

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
