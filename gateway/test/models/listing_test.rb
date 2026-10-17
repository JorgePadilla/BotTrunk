# frozen_string_literal: true

require "test_helper"

class ListingTest < ActiveSupport::TestCase
  test "slugs are URL-safe, unique and never a built-in's" do
    listing = build_listing
    assert listing.valid?

    listing.slug = "Bad Slug"
    assert_not listing.valid?
    listing.slug = "scrape-markdown"
    assert_includes listing.tap(&:valid?).errors[:slug], "is taken by a BotTrunk service"
    assert_not Listing.new(listing.attributes.except("id").merge("slug" => "company-lookup")).valid?, "already taken by the first"
  end

  test "the upstream must be https and public" do
    listing = build_listing
    listing.upstream_url = "http://api.seller.example/lookup"
    assert_not listing.valid?
    listing.upstream_url = "https://db.internal/lookup"
    assert_includes listing.tap(&:valid?).errors[:upstream_url].join, "private network"
  end

  test "the price is fixed once the listing has been live" do
    listing = live_listing
    listing.pause!
    listing.price_atomic = 90_000
    assert_not listing.valid?
    assert_match(/cannot change once the listing has been live/, listing.errors[:price_atomic].join)
  end

  test "the schema must be a list of named, typed fields; bad JSON is a form error" do
    listing = build_listing
    listing.inputs_json = "{ not json"
    assert_includes listing.tap(&:valid?).errors[:inputs], "is not valid JSON"

    listing = build_listing(slug: "other-api")
    listing.inputs = [ { "name" => "has space", "type" => "string", "description" => "x" } ]
    assert_not listing.valid?
    listing.inputs = []
    assert_includes listing.tap(&:valid?).errors[:inputs], "needs at least one field"
  end

  test "a live listing is a catalog entry like any other; drafts and paused ones are not" do
    draft = build_listing(slug: "draft-api")
    live = live_listing

    service = Catalog::Service.find("company-lookup")
    assert_equal "Verified seller", service.provider
    assert_equal 50_000, service.price_atomic
    assert_equal live.seller_id, service.seller_id
    assert service.seller_listing?
    assert_not service.built_in?
    assert_equal "number", service.inputs.first.name
    assert_nil Catalog::Service.find(draft.slug)

    live.pause!
    Current.listing_services = nil
    assert_nil Catalog::Service.find("company-lookup")
  end
end
