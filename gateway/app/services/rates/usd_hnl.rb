# frozen_string_literal: true

module Rates
  # Lempiras per US dollar, refreshed at most once an hour, on demand.
  #
  # Order: HNL_PER_USD (manual pin, wins outright) → the value refreshed within
  # the last hour → a fresh fetch from the Banco Central de Honduras Web API
  # (Rates::FetchBch, when BCH_API_KEY is set) → the open.er-api.com feed →
  # the newest stored rate (up to 7 days old) → a hard fallback. Every
  # successful fetch is stored in `exchange_rates`, so an outage degrades to
  # "an hour or a day old", never to a wrong number.
  class UsdHnl
    FEED = "https://open.er-api.com/v6/latest/USD"
    FALLBACK = BigDecimal("26.00")
    CACHE_KEY = "rates/usd_hnl"
    REFRESH_EVERY = 1.hour
    STALE_AFTER = 7.days

    Info = Data.define(:rate, :source, :as_of, :fetched_at)

    # Test hook: pin the rate (like Payments::Adapters.stubs_current).
    cattr_accessor :stub_rate

    def self.current = new.info.rate

    def self.info = new.info

    def info
      return Info.new(rate: BigDecimal(stub_rate.to_s), source: "stub", as_of: Date.current, fetched_at: Time.current) if stub_rate
      return Info.new(rate: BigDecimal(ENV["HNL_PER_USD"]), source: "manual", as_of: Date.current, fetched_at: Time.current) if ENV["HNL_PER_USD"].present?

      Rails.cache.fetch(CACHE_KEY, expires_in: REFRESH_EVERY, skip_nil: true) { refresh } || latest_stored(STALE_AFTER) || Info.new(rate: FALLBACK, source: "fallback", as_of: Date.current, fetched_at: Time.current)
    end

    # Fetch from the best available source and store it. Returns Info or nil.
    def refresh
      fetched = from_bch || from_feed
      return nil unless fetched

      row = ExchangeRate.create!(pair: "USD/HNL", source: fetched[:source], rate: fetched[:rate], as_of: fetched[:as_of], fetched_at: Time.current)
      Info.new(rate: row.rate, source: row.source, as_of: row.as_of, fetched_at: row.fetched_at)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("rates: could not store usd/hnl: #{e.message}")
      Info.new(rate: fetched[:rate], source: fetched[:source], as_of: fetched[:as_of], fetched_at: Time.current)
    end

    private

    def from_bch
      result = FetchBch.new.call
      return { source: "bch", rate: result[:rate], as_of: result[:as_of] } if result.success?

      Rails.logger.warn("rates: #{result.error}") unless result.code == :not_configured
      nil
    end

    def from_feed
      response = Faraday.new(request: { open_timeout: 3, timeout: 5 }).get(FEED)
      return nil unless response.success?

      rate = JSON.parse(response.body).dig("rates", "HNL")
      return nil unless rate.is_a?(Numeric) && rate.positive?

      { source: "feed", rate: BigDecimal(rate.to_s), as_of: Date.current }
    rescue Faraday::Error, JSON::ParserError => e
      Rails.logger.warn("rates: usd/hnl feed failed: #{e.message}")
      nil
    end

    def latest_stored(max_age)
      row = ExchangeRate.usd_hnl.where(fetched_at: max_age.ago..).newest_first.first
      row && Info.new(rate: row.rate, source: row.source, as_of: row.as_of, fetched_at: row.fetched_at)
    end
  end
end
