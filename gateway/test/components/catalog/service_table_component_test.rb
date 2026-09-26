# frozen_string_literal: true

require "test_helper"

class Catalog::ServiceTableComponentTest < ViewComponent::TestCase
  test "one row per service, variants included" do
    services = Catalog::Service.all.select { |s| s.category == "Payments" }
    render_inline Catalog::ServiceTableComponent.new(services: services)

    assert_selector "tbody tr", count: services.size
    assert_selector "a[href='/s/deposit-bac-10000']", text: /Deposit L10,000/
  end

  test "prices show cents above a dollar and full precision below it" do
    render_inline Catalog::ServiceTableComponent.new(
      services: [ Catalog::Service.find("deposit-bac-1000"), Catalog::Service.find("page-metadata") ]
    )

    assert_text "$42.51"      # not $42.510122
    assert_text "$0.02"
  end

  test "seven figures are delimited, because this column spans both ends" do
    render_inline Catalog::ServiceTableComponent.new(services: [ Catalog::Service.find("corridor-build") ])
    assert_text "$1,000,000.00"
  end

  test "paid calls show a dash until there are any" do
    render_inline Catalog::ServiceTableComponent.new(services: [ Catalog::Service.find("page-metadata") ])
    assert_selector "td", text: "—"

    render_inline Catalog::ServiceTableComponent.new(
      services: [ Catalog::Service.find("page-metadata") ],
      metrics: { "page-metadata" => Catalog::Metrics::Row.new(slug: "page-metadata", calls: 7, p50_ms: 100, success_rate: 1.0, volume: 1, last_at: nil) }
    )
    assert_selector "td", text: "7"
  end

  test "the price header is a sort toggle only when there is somewhere to link" do
    render_inline Catalog::ServiceTableComponent.new(services: [ Catalog::Service.find("page-metadata") ])
    assert_no_selector "thead a"

    render_inline Catalog::ServiceTableComponent.new(services: [ Catalog::Service.find("page-metadata") ],
                                                    path: "/services", params: { category: "Data" })
    assert_selector "thead a[href='/services?category=Data&sort=price']"

    # Clicking the active sort turns it off again.
    render_inline Catalog::ServiceTableComponent.new(services: [ Catalog::Service.find("page-metadata") ],
                                                    path: "/services", sort: "price")
    assert_selector "thead a[href='/services']"
  end
end
