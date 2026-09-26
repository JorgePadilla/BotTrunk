# frozen_string_literal: true

require "test_helper"

class Catalog::RankingTest < ActiveSupport::TestCase
  setup { Rails.cache.delete(Catalog::Metrics::CACHE_KEY) }

  test "collapses a family into one card priced at its cheapest tier" do
    card = Catalog::Ranking.new.cards.find { |c| c.primary.family == "deposit-bac" }

    assert_equal "deposit-bac-1000", card.primary.slug
    assert_equal 4, card.variants.size
    assert_equal "Payments", card.category
  end

  test "one card per service when there is no family" do
    assert_equal Catalog::Service.grouped.size, Catalog::Ranking.new.cards.size
  end

  test "what people pay for climbs, everything else keeps seed order" do
    settle("domain-dns", 3)
    slugs = Catalog::Ranking.new.cards.map { |c| c.primary.slug }

    assert_equal "domain-dns", slugs.first, "the most-bought service leads the catalog"
    untouched = slugs - [ "domain-dns" ]
    assert_equal untouched, Catalog::Service.grouped.map { |g| g.min_by(&:price_atomic).slug } - [ "domain-dns" ]
  end

  test "a family's calls are summed, so one tier's traffic lifts the card" do
    settle("deposit-bac-5000", 2)
    assert_equal "deposit-bac-1000", Catalog::Ranking.new.cards.first.primary.slug
  end

  test "on-request services sort after live ones" do
    with_real_statuses do
      live = Catalog::Ranking.new.cards.map(&:live?)
      assert_includes live, false, "the seed has on-request services to sort"
      assert_equal live.sort_by { |flag| flag ? 0 : 1 }, live
    end
  end

  test "sections come out in a deliberate order and drop the empty ones" do
    names = Catalog::Ranking.new.sections.map(&:first)

    assert_equal Catalog::Ranking::SECTIONS, names
    assert_equal Catalog::Service.categories.sort, names.sort, "every category has at least one service"
  end

  test "a category outside SECTIONS still gets a section, after the ordered ones" do
    extra = Catalog::Service.new(slug: "x", name: "X", category: "Zoology", provider: "us", summary: "s",
                                 description: "d", price_usdc: 1, network: "n", asset: "USDC",
                                 facilitator: "f", inputs: [], outputs: [])
    sections = Catalog::Ranking.new(Catalog::Service.all + [ extra ]).sections

    assert_equal "Zoology", sections.last.first
  end

  test "services lists every variant, not one per family" do
    assert_equal Catalog::Service.all.size, Catalog::Ranking.new.services.size
    assert_includes Catalog::Ranking.new.services.map(&:slug), "deposit-bac-10000"
  end

  test "by_price is cheapest first" do
    prices = Catalog::Ranking.new.by_price.map(&:price_atomic)
    assert_equal prices.sort, prices
  end

  private

  def with_real_statuses
    Catalog::Service.treat_all_live = false
    yield
  ensure
    Catalog::Service.treat_all_live = true
  end

  def settle(slug, count)
    count.times do
      Call.create!(service_slug: slug, pay_to: "G", network: "n", asset: "a", amount: 20_000, commission: 3_000,
                   seller_amount: 17_000, upstream_status: 200, upstream_latency_ms: 100, status: "settled")
    end
    Rails.cache.delete(Catalog::Metrics::CACHE_KEY)
  end
end
