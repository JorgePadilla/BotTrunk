require "test_helper"

class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "index lists the catalog" do
    get root_url
    assert_response :success
    assert_select "h1", text: "Your agent can pay a person."
    assert_select "a[href='/s/scrape-markdown']"
    assert_select "a[href='/s/deposit-bac-1000']", text: /Pay someone in Honduras/
    assert_select "a[href='/s/deposit-bac-10000']", count: 0, message: "the deposit tiers collapse into one card"
  end

  test "index shows measured numbers only when there are settled calls" do
    get root_url
    assert_select "p", text: /Live on Algorand MainNet/, count: 0 # the band is a div
    assert_match "Live on Algorand MainNet", response.body
    assert_no_match(/paid calls settled/, response.body)

    Call.create!(service_slug: "scrape-markdown", pay_to: "G", network: "n", asset: "a", amount: 90_000, commission: 13_500,
                 seller_amount: 76_500, upstream_status: 200, upstream_latency_ms: 812, status: "settled")
    get root_url
    assert_match "paid calls settled", response.body
    assert_match "$0.09", response.body
    assert_select "span", text: "per call · p50 812 ms"
  end

  test "page views are recorded with the referrer host, service pages with their slug" do
    get root_url, headers: { "Referer" => "https://www.npmjs.com/package/bottrunk-mcp", "User-Agent" => "Mozilla/5.0 Chrome" }
    get service_url("scrape-markdown"), headers: { "User-Agent" => "Mozilla/5.0 Chrome" }
    get api_v1_catalog_url, headers: { "User-Agent" => "bottrunk-mcp/0.1.0" }

    assert_equal %w[page_view page_view catalog_api], Event.order(:id).pluck(:name)
    assert_equal "npmjs.com", Event.first.referrer_host
    assert_equal "scrape-markdown", Event.second.service_slug
    assert_equal "bottrunk-mcp", Event.last.client
  end

  test "index filters by category" do
    get root_url(category: "Payments")
    assert_response :success
    assert_select "a[href='/s/deposit-bac-1000']"
    assert_select "a[href='/s/scrape-markdown']", count: 0
  end

  test "index searches by words in name, summary or category" do
    get root_url(q: "lempiras")
    assert_response :success
    assert_select "a[href='/s/deposit-bac-1000']"
    assert_select "a[href='/s/scrape-markdown']", count: 0
    assert_select "input[name=q][value=lempiras]"
  end

  test "index shows an empty state when nothing matches" do
    get root_url(q: "zzzz-nothing")
    assert_response :success
    assert_select "a[href^='/s/']", count: 0
    assert_select "p", text: "Nothing here yet."
    assert_select "a[href='/sell']"
  end

  test "a deposit page lists the other amounts and prices them live" do
    get service_url("deposit-bac-2500")
    assert_response :success
    assert_select "h1", text: "Deposit L2,500 to a BAC account"
    assert_select "a[href='/s/deposit-bac-10000']", text: /L10,000/
    assert_match "Other amounts", response.body
    assert_select "dd", text: "L2,500 at today's rate"
  end

  test "an on-request service asks for an email instead of a payment" do
    get service_url("verify-business-hn")
    assert_response :success
    assert_select "a[href^='mailto:hello@bottrunk.com']", text: "Request access"
    assert_select "a[href='/connect']", text: "Pay from your agent", count: 0
    assert_match "On request", response.body
  end

  test "show renders a service" do
    get service_url("scrape-markdown")
    assert_response :success
    assert_select "h1", text: "Scrape URL to Markdown"
    assert_select "pre", minimum: 1
    assert_select "a[role=tab][href='#call']", text: "Call it"
    assert_select "a[href='/connect']", text: "Pay from your agent"
  end

  test "a built-in service publishes how it behaves, including what it refuses" do
    get service_url("scrape-markdown")

    assert_select "h2", text: "How it behaves"
    assert_select "a[role=tab][href='#behaviour']", text: "Behaviour"
    assert_match "Refused with 422 and not charged", response.body
    assert_match "BotTrunk/0.1", response.body
    assert_match "render_js", response.body
  end

  test "a human-fulfilled service has no built-in limits to publish" do
    get service_url("verify-business-hn")

    assert_select "a[role=tab][href='#behaviour']", count: 0
  end

  test "theme cookie drives data-theme" do
    cookies[:theme] = "bottrunk-dark"
    get root_url
    assert_select "html[data-theme=bottrunk-dark]"
  end
end
