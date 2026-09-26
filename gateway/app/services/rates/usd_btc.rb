# frozen_string_literal: true

module Rates
  # US dollars per bitcoin, for quoting a delivery.
  #
  # Deliberately unlike Rates::UsdHnl in one way: a lempira rate six hours old
  # is still roughly true, and a bitcoin price six hours old is a different
  # number. So the refresh window is minutes, and a price we cannot refresh
  # past MAX_AGE is refused rather than served — a stale quote here is not a
  # rounding error, it is a loss on every call.
  #
  # Stored in `exchange_rates` under the USD/BTC pair, so the throttle is
  # durable and shared the way the lempira one is, rather than living in a
  # cache that a deploy wipes.
  class UsdBtc
    PAIR = "USD/BTC"
    FEED = "https://api.coinbase.com/v2/prices/BTC-USD/spot"
    REFRESH_EVERY = 5.minutes
    MAX_AGE = 30.minutes        # past this we have no price, and say so
    MEMO_FOR = 20.seconds
    CACHE_KEY = "rates/usd_btc"
    TIMEOUT = 5

    Info = Data.define(:rate, :source, :fetched_at)

    # Test hook: pin the price (like Rates::UsdHnl.stub_rate).
    cattr_accessor :stub_rate

    # Returns Info, or nil when there is no price fresh enough to quote on.
    def self.info = new.info

    def self.current = info&.rate

    def info
      return Info.new(rate: BigDecimal(stub_rate.to_s), source: "stub", fetched_at: Time.current) if stub_rate

      Rails.cache.fetch(CACHE_KEY, expires_in: MEMO_FOR, skip_nil: true) { fresh_info }
    rescue StandardError => e
      Rails.logger.info("usd_btc: #{e.class}: #{e.message}")
      stored_info(MAX_AGE)
    end

    private

    def fresh_info
      stored = stored_info(REFRESH_EVERY)
      return stored if stored

      fetched = fetch
      return stored_info(MAX_AGE) if fetched.nil?

      row = ExchangeRate.create!(pair: PAIR, rate: fetched, source: "coinbase", as_of: Date.current, fetched_at: Time.current)
      Info.new(rate: row.rate, source: row.source, fetched_at: row.fetched_at)
    end

    def stored_info(window)
      row = ExchangeRate.where(pair: PAIR).where(fetched_at: window.ago..).order(fetched_at: :desc).first
      row && Info.new(rate: row.rate, source: row.source, fetched_at: row.fetched_at)
    end

    def fetch
      response = connection.get(FEED)
      return nil unless response.success?

      amount = JSON.parse(response.body).dig("data", "amount")
      value = BigDecimal(amount.to_s)
      value.positive? ? value : nil
    rescue Faraday::Error, JSON::ParserError, ArgumentError, TypeError => e
      Rails.logger.info("usd_btc: feed failed (#{e.class})")
      nil
    end

    def connection
      Faraday.new(headers: { "Accept" => "application/json" }) do |f|
        f.options.open_timeout = TIMEOUT
        f.options.timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
