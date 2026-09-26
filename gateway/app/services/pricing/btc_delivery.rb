# frozen_string_literal: true

module Pricing
  # How much bitcoin a fixed USDC payment buys: the spot price marked up by a
  # spread, so the delivered amount is worth less than what was paid and the
  # difference covers the purchase, the network fee and the risk between
  # payment and send.
  #
  #   500 USDC at 100,000 spot with a 10 % spread → 500 / 110,000 = 0.00454545 BTC
  #
  # The mirror of Pricing::LempiraDeposit: there the buyer names the lempiras
  # and we compute the USDC; here the buyer pays a known USDC tier and we
  # compute what arrives. Both publish the effective rate, because a spread the
  # buyer cannot see is not a price, it is a trick — and this one is large.
  class BtcDelivery
    DEFAULT_SPREAD_BPS = 1_000   # 10 %
    SATOSHI = 100_000_000

    def initialize(usdc:, spot: Rates::UsdBtc.current, spread_bps: self.class.spread_bps)
      @usdc = BigDecimal(usdc.to_s)
      @spot = spot && BigDecimal(spot.to_s)
      @spread_bps = spread_bps.to_i
    end

    attr_reader :spot, :spread_bps

    def quotable? = @spot.present? && @spot.positive?

    # What the buyer is charged per bitcoin, spot plus the spread.
    def effective_rate = quotable? ? (@spot * (1 + BigDecimal(@spread_bps) / 10_000)).round(2) : nil

    # Rounded down to the satoshi: never promise more than we can send.
    def btc
      return nil unless quotable?

      (@usdc / effective_rate).round(8, BigDecimal::ROUND_DOWN)
    end

    def satoshis = btc && (btc * SATOSHI).to_i

    def spread_percent = (BigDecimal(@spread_bps) / 100).to_f

    # What the delivered bitcoin is worth at spot — the honest cost of the
    # spread, stated rather than buried.
    def value_at_spot = quotable? ? (btc * @spot).round(2) : nil

    def to_quote
      return nil unless quotable?

      {
        usdc_paid: @usdc.to_s("F"),
        btc_delivered: btc.to_s("F"),
        satoshis: satoshis,
        spot_usd_per_btc: @spot.to_s("F"),
        your_rate_usd_per_btc: effective_rate.to_s("F"),
        spread_percent: spread_percent,
        value_at_spot_usd: value_at_spot.to_s("F"),
        quoted_at: Time.current.utc.iso8601
      }
    end

    def self.spread_bps = ENV["BTC_SPREAD_BPS"].present? ? ENV["BTC_SPREAD_BPS"].to_i : DEFAULT_SPREAD_BPS
  end
end
