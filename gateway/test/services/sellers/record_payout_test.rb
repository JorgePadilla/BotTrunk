# frozen_string_literal: true

require "test_helper"

module Sellers
  class RecordPayoutTest < ActiveSupport::TestCase
    TXID = "B" * 52

    setup do
      @listing = live_listing
      @seller = @listing.seller
      2.times do |i|
        Call.create!(service_slug: @listing.slug, seller: @seller, pay_to: "G", network: "algorand:x", asset: "31566704",
                     amount: 2_000_000, commission: 300_000, seller_amount: 1_700_000, transaction_id: "T#{i}", status: "settled")
      end
    end

    def record(amount, txid = TXID) = RecordPayout.new(seller: @seller, amount_usdc: amount, transaction_id: txid).call

    test "a payout is recorded, lowers what is owed and emails the seller the transaction" do
      result = perform_enqueued_jobs { record("3.40") }

      assert result.success?
      assert_equal 3_400_000, result[:payout].amount
      assert_equal 0, @seller.reload.owed_atomic
      mail = ActionMailer::Base.deliveries.last
      assert_equal [ @seller.email ], mail.to
      assert_match "https://allo.info/tx/#{TXID}", mail.text_part.body.to_s
    end

    test "more than is owed is refused, so a slipped decimal never becomes a balance" do
      result = record("34.00")
      assert_equal :over_owed, result.code
      assert_equal 0, Payout.count
    end

    test "a bad amount or transaction id is refused" do
      assert_equal :invalid, record("lots").code
      assert_equal :invalid, record("1.00", "not-a-txid").code
      record("1.00")
      assert_equal :invalid, record("1.00").code, "the same transaction cannot be recorded twice"
    end
  end
end
