# frozen_string_literal: true

module Rates
  # Lempiras per US dollar. Source, in order: a manual override (ENV
  # HNL_PER_USD — use it when the feed looks wrong), then the open.er-api.com
  # daily feed (cached 12 h), then a hard fallback so pricing never raises.
  # The Banco Central de Honduras reference rate moves a few centavos a week,
  # so a day-old figure is fine; the spread applied on top (Pricing::LempiraDeposit)
  # is what protects the margin.
  class UsdHnl
    FEED = "https://open.er-api.com/v6/latest/USD"
    FALLBACK = BigDecimal("26.00")
    CACHE_KEY = "rates/usd_hnl"
    TTL = 12.hours

    # Test hook: pin the rate (like Payments::Adapters.stubs_current).
    cattr_accessor :stub_rate

    def self.current = new.current

    def current
      return BigDecimal(stub_rate.to_s) if stub_rate
      return BigDecimal(ENV["HNL_PER_USD"]) if ENV["HNL_PER_USD"].present?

      Rails.cache.fetch(CACHE_KEY, expires_in: TTL) { fetch } || FALLBACK
    end

    private

    def fetch
      response = Faraday.new(request: { open_timeout: 3, timeout: 5 }).get(FEED)
      return nil unless response.success?

      rate = JSON.parse(response.body).dig("rates", "HNL")
      rate.is_a?(Numeric) && rate.positive? ? BigDecimal(rate.to_s) : nil
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("rates: usd/hnl feed failed: #{e.message}")
      nil
    end
  end
end
