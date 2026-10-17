# frozen_string_literal: true

require "test_helper"

module Sellers
  class ListingsControllerTest < ActionDispatch::IntegrationTest
    PARAMS = {
      name: "Company lookup", slug: "company-lookup", summary: "Legal name for a registration number.", category: "Data",
      upstream_url: "https://api.seller.example/lookup", price_usdc: "0.05",
      inputs_json: '[{"name":"number","type":"string","description":"Registration number."}]',
      outputs_json: '[{"name":"name","type":"string","description":"Legal name."}]'
    }.freeze

    setup do
      @seller = build_seller
      sign_in_as(@seller)
    end

    test "a seller drafts a listing, then submits it for review and the operator is told" do
      post seller_listings_path, params: { listing: PARAMS }
      assert_redirected_to seller_root_path
      listing = @seller.listings.last
      assert_equal "draft", listing.status
      assert_equal 50_000, listing.price_atomic

      with_admin_email do
        perform_enqueued_jobs { post submit_seller_listing_path(listing) }
      end
      assert_equal "pending", listing.reload.status
      assert_match "Listing to review — Company lookup", ActionMailer::Base.deliveries.last.subject
    end

    test "a listing with mistakes comes back with them" do
      post seller_listings_path, params: { listing: PARAMS.merge(upstream_url: "http://plain.example", inputs_json: "nope") }
      assert_response :unprocessable_entity
      assert_select "li", text: /must start with https/
      assert_select "li", text: /not valid JSON/
    end

    test "no payout address, no submission" do
      @seller.update!(payout_address: nil)
      listing = build_listing(seller: @seller)
      post submit_seller_listing_path(listing)
      assert_equal "draft", listing.reload.status
      assert_match(/payout address/, flash[:alert])
    end

    test "no accepted terms, no submission; accepting them unblocks it" do
      @seller.update!(terms_version: nil)
      listing = build_listing(seller: @seller)
      post submit_seller_listing_path(listing)
      assert_equal "draft", listing.reload.status

      post seller_accept_terms_path, params: { accept: "1" }
      assert_equal Seller::TERMS_VERSION, @seller.reload.terms_version
      post submit_seller_listing_path(listing)
      assert_equal "pending", listing.reload.status
    end

    test "the terms are accepted only with the box ticked" do
      @seller.update!(terms_version: nil)
      post seller_accept_terms_path
      assert_nil @seller.reload.terms_version
    end

    test "a live listing must be paused before it is edited, and its price stays fixed" do
      listing = live_listing(seller: @seller)
      get edit_seller_listing_path(listing)
      assert_redirected_to seller_root_path

      post pause_seller_listing_path(listing)
      assert_equal "paused", listing.reload.status
      patch seller_listing_path(listing), params: { listing: { summary: "Sharper summary.", price_usdc: "9.99" } }
      assert_equal "Sharper summary.", listing.reload.summary
      assert_equal 50_000, listing.price_atomic, "the price field is ignored once the listing has been live"
    end

    test "one seller cannot touch another's listing" do
      other = build_listing(seller: build_seller, slug: "not-yours")
      post submit_seller_listing_path(other)
      assert_response :not_found
    end

    test "the dashboard lists the seller's APIs" do
      build_listing(seller: @seller)
      get seller_root_path
      assert_select "td", text: /Company lookup/
      assert_select "button", text: "Submit for review"
    end
  end
end
