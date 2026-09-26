# frozen_string_literal: true

require "test_helper"

module Pricing
  class BtcDeliveryTest < ActiveSupport::TestCase
    test "the buyer pays spot plus the spread, and the cost of that is published" do
      quote = BtcDelivery.new(usdc: 500, spot: 100_000, spread_bps: 1_000)

      assert_equal BigDecimal("110000"), quote.effective_rate
      assert_equal BigDecimal("0.00454545"), quote.btc
      assert_equal 454_545, quote.satoshis
      assert_equal 10.0, quote.spread_percent
      assert_equal BigDecimal("454.55"), quote.value_at_spot, "what arrives is worth this at spot — the spread, stated"
    end

    test "bitcoin is rounded down to the satoshi, never up" do
      quote = BtcDelivery.new(usdc: 100, spot: 99_999.99, spread_bps: 0)

      assert_equal BigDecimal("0.00100000"), quote.btc
      assert_operator quote.btc * quote.effective_rate, :<=, BigDecimal("100"), "never promise more than was paid for"
    end

    test "a different spread changes the rate and nothing else" do
      tight = BtcDelivery.new(usdc: 500, spot: 100_000, spread_bps: 100)

      assert_equal BigDecimal("101000"), tight.effective_rate
      assert_equal 1.0, tight.spread_percent
      assert_operator tight.btc, :>, BtcDelivery.new(usdc: 500, spot: 100_000, spread_bps: 1_000).btc
    end

    test "no price means no quote, rather than a guess" do
      quote = BtcDelivery.new(usdc: 500, spot: nil)

      assert_not quote.quotable?
      assert_nil quote.btc
      assert_nil quote.effective_rate
      assert_nil quote.to_quote
    end

    test "the quote carries every number the buyer needs to judge it" do
      out = BtcDelivery.new(usdc: 1_000, spot: 100_000, spread_bps: 1_000).to_quote

      assert_equal "1000.0", out[:usdc_paid]
      assert_equal "0.0090909", out[:btc_delivered]
      assert_equal "100000.0", out[:spot_usd_per_btc]
      assert_equal "110000.0", out[:your_rate_usd_per_btc]
      assert_equal "909.09", out[:value_at_spot_usd]
      assert out[:quoted_at].present?
    end

    test "the spread comes from the environment, so it is one change not a deploy of new maths" do
      ENV["BTC_SPREAD_BPS"] = "250"
      assert_equal 250, BtcDelivery.spread_bps
    ensure
      ENV.delete("BTC_SPREAD_BPS")
    end
  end
end
