# frozen_string_literal: true

require "test_helper"

class ServiceRequestTest < ActiveSupport::TestCase
  def build(**attrs)
    ServiceRequest.new({ email: "buyer@example.com", details: "We need daily court filings from three Honduran courts." }.merge(attrs))
  end

  test "a request with no service names the gap rather than failing" do
    request = build(service_slug: nil)

    assert request.valid?
    assert request.for_catalog_gap?
    assert_nil request.service
  end

  test "a slug we do not sell is refused" do
    request = build(service_slug: "not-a-service")

    assert_not request.valid?
    assert_includes request.errors[:service_slug], "is not a service we list"
  end

  test "a slug we do sell resolves to the catalog entry" do
    request = build(service_slug: "scrape-markdown")

    assert request.valid?
    assert_equal "Scrape URL to Markdown", request.service.name
    assert_not request.for_catalog_gap?
  end

  test "details too short to act on are refused, with a message that says why" do
    request = build(details: "need scraping")

    assert_not request.valid?
    assert_match(/sentence or two/, request.errors[:details].to_sentence)
  end

  test "a budget is optional but must be positive when given" do
    assert build(budget_atomic: nil).valid?
    assert build(budget_atomic: 5_000_000).valid?
    assert_not build(budget_atomic: 0).valid?
  end

  test "answering records who decided and when, not just that someone did" do
    request = build.tap(&:save!)

    request.answer!(notes: "Quoted 12 USDC.")

    assert_equal "answered", request.status
    assert_equal "Quoted 12 USDC.", request.review_notes
    assert request.reviewed_at.present?
    assert_not request.pending?
  end
end
