# frozen_string_literal: true

require "test_helper"

module Pricing
  class LempiraDepositTest < ActiveSupport::TestCase
    test "applies the spread to the rate, then the fee, rounding up" do
      p = LempiraDeposit.new(amount_hnl: 1_000, rate: "26.20", spread: "1.50", fee_bps: 500)
      assert_equal BigDecimal("24.70"), p.effective_rate
      assert_equal BigDecimal("42.510122"), p.price_usdc # 1000 / 24.70 × 1.05 = 42.5101214…
      assert_equal 42_510_122, p.price_atomic
    end

    test "defaults come from the environment: L1.50 spread and 5 %" do
      p = LempiraDeposit.new(amount_hnl: 10_000)
      assert_equal BigDecimal("24.70"), p.effective_rate
      assert_equal 500, p.fee_bps
      assert_equal 425_101_215, p.price_atomic
    end

    test "catalog tiers price themselves from the day's rate" do
      tier = Catalog::Service.find("deposit-bac-2500")
      assert tier.lempira?
      assert_equal 2_500, tier.price_hnl
      assert_equal 106_275_304, tier.price_atomic
      assert_equal BigDecimal("106.275304"), tier.usd_price
      assert_equal 5000, Catalog::Service.find("scrape-markdown").price_atomic
    end
  end
end
