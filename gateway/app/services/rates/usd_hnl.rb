# frozen_string_literal: true

module Rates
  # Lempiras per US dollar, refreshed four times a day, on demand.
  #
  # Order: HNL_PER_USD (manual pin, wins outright) → the stored rate if it was
  # confirmed within the refresh window → a fresh fetch from the Banco Central
  # de Honduras Web API (Rates::FetchBch, when BCH_API_KEY is set) → the
  # open.er-api.com feed → the newest stored rate (up to 7 days old) → a hard
  # fallback. An outage degrades to "six hours or a day old", never to a wrong
  # number.
  #
  # **The window is enforced from the database, not from Rails.cache.** It was
  # a cache TTL, and the rate was being fetched every few minutes: a cache miss
  # is invisible, and a cache that is per-process, wiped by a deploy, or
  # failing to write silently turns "once an hour" into "once per page view".
  # `exchange_rates.fetched_at` is durable and shared, so the throttle holds
  # however many processes are running and whatever the cache is doing.
  class UsdHnl
    FEED = "https://open.er-api.com/v6/latest/USD"
    FALLBACK = BigDecimal("26.00")
    CACHE_KEY = "rates/usd_hnl"
    REFRESH_EVERY = 6.hours # four times a day
    MEMO_FOR = 60.seconds   # avoids one query per priced service on a page render
    STALE_AFTER = 7.days

    Info = Data.define(:rate, :source, :as_of, :fetched_at)

    # Test hook: pin the rate (like Payments::Adapters.stubs_current).
    cattr_accessor :stub_rate

    def self.current = new.info.rate

    def self.info = new.info

    def info
      return Info.new(rate: BigDecimal(stub_rate.to_s), source: "stub", as_of: Date.current, fetched_at: Time.current) if stub_rate
      return Info.new(rate: BigDecimal(ENV["HNL_PER_USD"]), source: "manual", as_of: Date.current, fetched_at: Time.current) if ENV["HNL_PER_USD"].present?

      Rails.cache.fetch(CACHE_KEY, expires_in: MEMO_FOR, skip_nil: true) { current_info } ||
        Info.new(rate: FALLBACK, source: "fallback", as_of: Date.current, fetched_at: Time.current)
    end

    def current_info
      latest_stored(REFRESH_EVERY) || refresh || latest_stored(STALE_AFTER)
    end

    # Fetch from the best available source and store it. Returns Info or nil.
    def refresh
      fetched = from_bch || from_feed
      return nil unless fetched

      row = store(fetched)
      Info.new(rate: row.rate, source: row.source, as_of: row.as_of, fetched_at: row.fetched_at)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("rates: could not store usd/hnl: #{e.message}")
      Info.new(rate: fetched[:rate], source: fetched[:source], as_of: fetched[:as_of], fetched_at: Time.current)
    end

    private

    # The table is a history of the *rate*, not of our polling. The lempira
    # moves a few times a month; writing a row every time we confirm the same
    # number buried the one thing the history is for — when it changed — under
    # two dozen identical lines. Same number from the same source: move
    # `fetched_at` forward on the row that is already there.
    def store(fetched)
      latest = ExchangeRate.usd_hnl.newest_first.first
      if latest && latest.rate == fetched[:rate] && latest.source == fetched[:source] && latest.as_of == fetched[:as_of]
        latest.update!(fetched_at: Time.current)
        return latest
      end

      ExchangeRate.create!(pair: "USD/HNL", source: fetched[:source], rate: fetched[:rate], as_of: fetched[:as_of], fetched_at: Time.current)
    end

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
