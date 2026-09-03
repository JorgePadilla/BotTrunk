# frozen_string_literal: true

require "test_helper"

class Catalog::ServiceCardComponentTest < ViewComponent::TestCase
  test "shows name, summary, price, latency and provider" do
    service = Catalog::Service.find("scrape-markdown")
    render_inline(Catalog::ServiceCardComponent.new(service: service))
    assert_selector "a[href='/s/scrape-markdown']"
    assert_text "Scrape URL to Markdown"
    assert_text "$0.005"
    assert_text "per call · 0.8 s"
    assert_text "By BotTrunk"
  end
end
