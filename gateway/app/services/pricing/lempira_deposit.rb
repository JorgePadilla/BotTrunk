# frozen_string_literal: true

module Pricing
  # USDC price of a lempira deposit: the buyer gets `spread` lempiras per
  # dollar less than the reference rate, then a fee on top. Integer µUSDC out,
  # rounded up so we never undercharge by a micro-cent.
  #
  #   L1,000 at 26.20 reference, 1.50 spread, 5 % fee → 1000 / 24.70 × 1.05 = 42.51 USDC
  class LempiraDeposit
    DEFAULT_SPREAD = BigDecimal("1.50")
    DEFAULT_FEE_BPS = 500

    def initialize(amount_hnl:, rate: Rates::UsdHnl.current, spread: self.class.spread, fee_bps: self.class.fee_bps)
      @amount_hnl = BigDecimal(amount_hnl.to_s)
      @rate = BigDecimal(rate.to_s)
      @spread = BigDecimal(spread.to_s)
      @fee_bps = fee_bps.to_i
    end

    attr_reader :rate, :fee_bps

    # Lempiras per dollar the buyer actually gets.
    def effective_rate = @rate - @spread

    def price_usdc = (@amount_hnl / effective_rate * (1 + BigDecimal(@fee_bps) / 10_000)).round(6, BigDecimal::ROUND_UP)

    def price_atomic = (price_usdc * 1_000_000).to_i

    def self.spread = ENV["HNL_RATE_SPREAD"].present? ? BigDecimal(ENV["HNL_RATE_SPREAD"]) : DEFAULT_SPREAD

    def self.fee_bps = ENV["DEPOSIT_FEE_BPS"].present? ? ENV["DEPOSIT_FEE_BPS"].to_i : DEFAULT_FEE_BPS
  end
end
