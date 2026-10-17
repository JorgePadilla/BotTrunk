# frozen_string_literal: true

require "test_helper"

module Sellers
  class ListingFormComponentTest < ViewComponent::TestCase
    test "a new listing can set its slug and price" do
      render_inline(ListingFormComponent.new(listing: Listing.new(price_atomic: 50_000, inputs: [], outputs: []), url: "/seller/listings"))
      assert_selector "input[name='listing[slug]']:not([disabled])"
      assert_selector "input[name='listing[price_usdc]'][value='0.05']:not([disabled])"
    end

    test "a listing that has been live locks slug and price and says why" do
      render_inline(ListingFormComponent.new(listing: Listing.new(went_live_at: Time.current, price_atomic: 50_000, inputs: [], outputs: []), url: "/x", method: :patch))
      assert_selector "input[name='listing[slug]'][disabled]"
      assert_selector "input[name='listing[price_usdc]'][disabled]"
      assert_text "Slug and price are fixed"
    end
  end
end
