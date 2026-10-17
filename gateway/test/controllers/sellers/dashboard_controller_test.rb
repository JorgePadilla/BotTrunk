# frozen_string_literal: true

require "test_helper"

module Sellers
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    setup do
      @listing = live_listing
      @seller = @listing.seller
      Call.create!(service_slug: @listing.slug, seller: @seller, pay_to: "GATEWAY", network: "algorand:x", asset: "31566704",
                   amount: 50_000, commission: 7_500, seller_amount: 42_500, payer_address: "PAYERADDRESSXYZ", transaction_id: "T1",
                   status: "settled", upstream_status: 200, upstream_latency_ms: 80)
      sign_in_as(@seller)
    end

    test "the dashboard shows what is owed, the calls, the APIs and how to check our signature" do
      get seller_root_path
      assert_response :success
      assert_select "dd", text: "$0.0425"
      assert_select "td", text: "company-lookup"
      assert_select "h2", text: "Check that a call came through BotTrunk"
      assert_select "[data-clipboard-text-value='#{@seller.signing_secret}']"
    end

    test "rotating the secret replaces it and the next forwarded call uses the new one" do
      old = @seller.signing_secret
      post seller_rotate_secret_path
      assert_redirected_to seller_root_path(anchor: "secret")
      assert_not_equal old, @seller.reload.signing_secret
    end

    test "someone signed out sees none of it" do
      delete seller_sign_out_path
      get seller_root_path
      assert_redirected_to seller_sign_in_path
    end
  end
end
