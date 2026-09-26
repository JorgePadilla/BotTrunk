require "test_helper"

class CatalogControllerTest < ActionDispatch::IntegrationTest
  test "index lists the catalog" do
    get root_url
    assert_response :success
    assert_select "h1", text: "Services your agent can buy."
    assert_select "a[href='/s/scrape-markdown']"
    assert_select "a[href='/s/deposit-bac-1000']", text: /Pay a person's bank account/
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

  test "index groups into sections, capped, with a way to the rest of each one" do
    get root_url
    assert_select "h2", text: "Payments"
    assert_select "h2", text: "Data"
    # Data is longer than a section shows, so it links to its own filtered page.
    assert_select "a[href='/?category=Data']", text: /See all \d+ in Data/
    assert_select "a[href='/services']", text: "see the whole list"
    # No section renders more cards than the cap, however long the category is.
    assert_select "section" do |sections|
      sections.each { |section| assert_operator section.css("a[href^='/s/']").size, :<=, Catalog::SectionComponent::LIMIT }
    end
  end

  test "a filtered view is a plain grid with pages, and paging keeps the filter" do
    with_many_services do
      get root_url(category: "Data")
      assert_response :success
      assert_select "h2", text: "Data", count: 0, message: "a narrowed catalog is a grid, not sections"
      assert_select "a[href^='/s/']", count: CatalogController::PER_PAGE
      assert_select "a[rel=next][href='/?category=Data&page=2']"

      get root_url(category: "Data", page: 2)
      assert_select "a[rel=prev][href='/?category=Data']"
      assert_select "a[href^='/s/']", minimum: 1
    end
  end

  test "a page past the end shows the last page instead of an empty screen" do
    get root_url(category: "Payments", page: 99)
    assert_response :success
    assert_select "a[href='/s/deposit-bac-1000']"
  end

  test "the reference page lists every service, variants included" do
    get services_url
    assert_response :success
    assert_select "h1", text: "Every service."
    assert_select "tbody tr", count: Catalog::Service.all.size
    assert_select "a[href='/s/deposit-bac-10000']", text: /Deposit L10,000/
    assert_select "a[href='/s/scrape-markdown']"
  end

  test "the reference page paginates, filters, searches and sorts by price" do
    with_many_services do
      get services_url
      assert_select "tbody tr", count: CatalogController::PER_PAGE_ALL
      assert_select "a[rel=next][href='/services?page=2']"
    end

    get services_url(category: "Payments")
    assert_select "tbody tr", count: Catalog::Service.all.count { |s| s.category == "Payments" }
    assert_select "a[href='/s/scrape-markdown']", count: 0

    get services_url(q: "lempiras")
    assert_select "a[href='/s/deposit-bac-1000']"

    get services_url(sort: "price")
    assert_response :success
    prices = css_select("tbody tr td:nth-child(3)").map { |td| td.text.strip.delete("$,").to_f }
    assert_equal prices.sort, prices
  end

  test "the reference page says when nothing matches" do
    get services_url(q: "zzzz-nothing")
    assert_response :success
    assert_select "tbody tr", count: 0
    assert_select "p", text: "Nothing here yet."
  end

  test "a hundred services still render one screen of sections and a paged reference" do
    with_many_services do
      get root_url
      assert_response :success
      cards = css_select("a[href^='/s/']").size
      assert_operator cards, :<=, Catalog::Ranking::SECTIONS.size * Catalog::SectionComponent::LIMIT

      get services_url
      assert_response :success
      assert_select "tbody tr", count: CatalogController::PER_PAGE_ALL
      assert_select "a[rel=next]"
    end
  end

  # The machine surfaces are not paginated: mcp-hub reads the API once at
  # startup with no cursor, so a truncated list silently deletes tools.
  test "pagination never reaches the API, llms.txt or the well-known files" do
    with_many_services do
      get api_v1_catalog_url
      assert_equal Catalog::Service.all.size, response.parsed_body["services"].size

      get api_v1_catalog_url(page: 2)
      assert_equal Catalog::Service.all.size, response.parsed_body["services"].size

      get llms_url
      assert_equal 100, response.body.scan("/s/scale-").size, "llms.txt lists every service"

      get well_known_x402_url
      assert_equal Catalog::Service.all.count(&:live?), response.parsed_body["resources"].size
    end
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
    get service_url("test-on-request")
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
    get service_url("test-on-request")

    assert_select "a[role=tab][href='#behaviour']", count: 0
  end

  test "theme cookie drives data-theme" do
    cookies[:theme] = "bottrunk-dark"
    get root_url
    assert_select "html[data-theme=bottrunk-dark]"
  end

  private

  # A hundred extra services, to prove the pages degrade the way they should.
  def with_many_services
    baseline = Catalog::Service.extra
    Catalog::Service.extra = baseline + Array.new(100) { |i|
      Catalog::Service.new(
        slug: "scale-#{i}", name: "Scale test #{i}", category: "Data", provider: "BotTrunk",
        summary: "Exists only while this test runs.", description: "Exists only while this test runs.",
        price_usdc: 0.01, network: "Algorand TestNet", asset: "USDC", facilitator: "GoPlausible",
        inputs: [ Catalog::Field.new("url", "string", "Anything.") ],
        outputs: [ Catalog::Field.new("ok", "boolean", "Whatever.") ]
      )
    }
    yield
  ensure
    Catalog::Service.extra = baseline
  end
end
