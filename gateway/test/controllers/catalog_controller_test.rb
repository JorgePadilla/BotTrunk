require "test_helper"

class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "index lists the catalog" do
    get root_url
    assert_response :success
    assert_select "h1", text: "Services your agent can pay for."
    assert_select "a[href='/s/scrape-markdown']"
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
    get root_url(category: "Messaging")
    assert_response :success
    assert_select "a[href='/s/send-whatsapp']"
    assert_select "a[href='/s/scrape-markdown']", count: 0
  end

  test "index searches by words in name, summary or category" do
    get root_url(q: "whatsapp")
    assert_response :success
    assert_select "a[href='/s/send-whatsapp']"
    assert_select "a[href='/s/scrape-markdown']", count: 0
    assert_select "input[name=q][value=whatsapp]"
  end

  test "index shows an empty state when nothing matches" do
    get root_url(q: "zzzz-nothing")
    assert_response :success
    assert_select "a[href^='/s/']", count: 0
    assert_select "p", text: "Nothing here yet."
    assert_select "a[href='/sell']"
  end

  test "show renders a service" do
    get service_url("scrape-markdown")
    assert_response :success
    assert_select "h1", text: "Scrape URL to Markdown"
    assert_select "pre", minimum: 1
    assert_select "a[role=tab][href='#call']", text: "Call it"
    assert_select "a[href='/docs#connect']", text: "Pay from your agent"
  end

  test "theme cookie drives data-theme" do
    cookies[:theme] = "bottrunk-dark"
    get root_url
    assert_select "html[data-theme=bottrunk-dark]"
  end
end
