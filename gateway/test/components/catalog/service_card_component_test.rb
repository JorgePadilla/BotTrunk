# frozen_string_literal: true

require "test_helper"

class Catalog::ServiceCardComponentTest < ViewComponent::TestCase
  test "shows name, summary, price and provider, with no performance claim until there are calls" do
    render_inline(Catalog::ServiceCardComponent.new(service: Catalog::Service.find("scrape-markdown")))

    assert_selector "a[href='/s/scrape-markdown']"
    assert_text "Scrape URL to Markdown"
    assert_text "$0.09"
    assert_text "per call"
    assert_no_text "p50"
    assert_text "By BotTrunk"
  end

  test "shows measured latency and success rate when the ledger has them" do
    metrics = Catalog::Metrics::Row.new(slug: "scrape-markdown", calls: 12, p50_ms: 812.0, success_rate: 1.0, volume: 1_080_000, last_at: Time.current)
    render_inline(Catalog::ServiceCardComponent.new(service: Catalog::Service.find("scrape-markdown"), metrics: metrics))

    assert_text "per call · p50 812 ms"
    assert_no_text "success"
  end

  test "a family renders as one card labelled with the range" do
    tiers = Catalog::Service.find("deposit-bac-1000").variants
    render_inline(Catalog::ServiceCardComponent.new(service: tiers.first, metrics: nil, variants: tiers))

    assert_text "Pay a person's bank account"
    assert_text "4 amounts · L1,000 – L10,000"
    assert_text "from"
    assert_text "$42.51"
    assert_no_text "Deposit L1,000"
  end

  test "an on-request service is badged" do
    render_inline(Catalog::ServiceCardComponent.new(service: Catalog::Service.find("verify-business-hn")))
    assert_text "On request"
    assert_text "$45.00"
  end
end
