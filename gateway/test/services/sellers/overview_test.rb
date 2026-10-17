# frozen_string_literal: true

require "test_helper"

module Sellers
  class OverviewTest < ActiveSupport::TestCase
    def settled_call(listing, at:, txn:)
      Call.create!(service_slug: listing.slug, seller: listing.seller, pay_to: "GATEWAY", network: "algorand:x", asset: "31566704",
                   amount: 50_000, commission: 7_500, seller_amount: 42_500, payer_address: "PAYER", transaction_id: txn,
                   status: "settled", upstream_status: 200, upstream_latency_ms: 80, created_at: at)
    end

    test "earned, paid and owed come from the seller's own calls and payouts" do
      listing = live_listing
      seller = listing.seller
      settled_call(listing, at: 2.days.ago, txn: "T1")
      settled_call(listing, at: 40.days.ago, txn: "T2")
      Call.create!(service_slug: "page-kind", pay_to: "GATEWAY", network: "algorand:x", asset: "31566704", amount: 20_000,
                   commission: 3_000, seller_amount: 17_000, transaction_id: "OURS", status: "settled")
      seller.payouts.create!(amount: 40_000, transaction_id: "A" * 52, paid_at: 1.day.ago)

      r = Overview.new(seller: seller).call[:report]
      assert_equal 85_000, r.earned, "a built-in call is never a seller's"
      assert_equal 40_000, r.paid
      assert_equal 45_000, r.owed
      assert_equal 85_000, seller.owed_atomic + seller.paid_atomic

      week = r.windows.find { |w| w.label == "7 days" }
      assert_equal 1, week.calls
      assert_equal 42_500, week.earned
      assert_equal 2, r.windows.find { |w| w.label == "All time" }.calls

      row = r.listings.first
      assert_equal 1, row.calls, "the per-API numbers cover the last 30 days"
      assert_equal 42_500, row.earned
      assert_equal %w[T1 T2], r.recent_calls.map(&:transaction_id)
    end
  end
end
