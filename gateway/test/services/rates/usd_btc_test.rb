# frozen_string_literal: true

require "test_helper"

module Rates
  class UsdBtcTest < ActiveSupport::TestCase
    setup do
      UsdBtc.stub_rate = nil
      Rails.cache.delete(UsdBtc::CACHE_KEY)
    end

    teardown { UsdBtc.stub_rate = nil }

    def stub_feed(amount)
      stub_request(:get, UsdBtc::FEED)
        .to_return(status: 200, body: { data: { base: "BTC", currency: "USD", amount: amount } }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    test "fetches the spot price and stores it against the pair" do
      stub_feed("104250.42")

      info = UsdBtc.info
      assert_equal BigDecimal("104250.42"), info.rate
      assert_equal "coinbase", info.source

      row = ExchangeRate.where(pair: "USD/BTC").last
      assert_equal BigDecimal("104250.42"), row.rate
    end

    test "a price fetched moments ago is reused instead of asking again" do
      ExchangeRate.create!(pair: "USD/BTC", rate: 99_000, source: "coinbase", as_of: Date.current, fetched_at: 1.minute.ago)

      assert_equal BigDecimal("99000"), UsdBtc.info.rate
      assert_not_requested :get, UsdBtc::FEED
    end

    test "a price past the refresh window is replaced" do
      ExchangeRate.create!(pair: "USD/BTC", rate: 99_000, source: "coinbase", as_of: Date.current, fetched_at: 20.minutes.ago)
      stub_feed("101000.00")

      assert_equal BigDecimal("101000"), UsdBtc.info.rate
      assert_requested :get, UsdBtc::FEED
    end

    # The difference from the lempira rate, and the reason this class exists:
    # a stale bitcoin price is not a slightly old number, it is a wrong one.
    test "a feed outage falls back only as far as MAX_AGE, then gives up" do
      ExchangeRate.create!(pair: "USD/BTC", rate: 99_000, source: "coinbase", as_of: Date.current, fetched_at: 10.minutes.ago)
      stub_request(:get, UsdBtc::FEED).to_return(status: 500)

      assert_equal BigDecimal("99000"), UsdBtc.info.rate, "ten minutes old is still quotable"

      ExchangeRate.update_all(fetched_at: 2.hours.ago)
      Rails.cache.delete(UsdBtc::CACHE_KEY)
      assert_nil UsdBtc.info, "two hours old is not a price, and nil says so"
      assert_nil UsdBtc.current
    end

    test "a feed that answers with nonsense is treated as no price" do
      stub_request(:get, UsdBtc::FEED).to_return(status: 200, body: "not json", headers: { "Content-Type" => "application/json" })

      assert_nil UsdBtc.info
    end

    test "the stub hook pins the price for other tests" do
      UsdBtc.stub_rate = "100000"

      assert_equal BigDecimal("100000"), UsdBtc.current
      assert_not_requested :get, UsdBtc::FEED
    end
  end
end
