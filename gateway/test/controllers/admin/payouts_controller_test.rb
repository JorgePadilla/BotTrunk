# frozen_string_literal: true

require "test_helper"

module Admin
  class PayoutsControllerTest < ActionDispatch::IntegrationTest
    setup do
      ENV["ADMIN_PASSWORD"] = "s3cret"
      @listing = live_listing
      Call.create!(service_slug: @listing.slug, seller: @listing.seller, pay_to: "G", network: "algorand:x", asset: "31566704",
                   amount: 2_000_000, commission: 300_000, seller_amount: 1_700_000, transaction_id: "T1", status: "settled")
    end

    teardown { ENV.delete("ADMIN_PASSWORD") }

    def auth = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret") }

    test "lists what each seller is owed and where to send it, and records a payout" do
      get admin_payouts_path, headers: auth
      assert_response :success
      assert_select "span", text: "$1.70"
      assert_select "dd", text: SellerHelpers::PAYOUT

      post admin_payouts_path, params: { seller_id: @listing.seller_id, amount_usdc: "1.70", transaction_id: "C" * 52 }, headers: auth
      assert_redirected_to admin_payouts_path
      assert_match "Recorded $1.70", flash[:notice]
      assert_equal 0, @listing.seller.reload.owed_atomic
    end

    test "a refused payout says why" do
      post admin_payouts_path, params: { seller_id: @listing.seller_id, amount_usdc: "17.00", transaction_id: "C" * 52 }, headers: auth
      assert_match "more than", flash[:alert]
    end
  end
end
