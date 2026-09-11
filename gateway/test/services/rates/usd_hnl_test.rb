# frozen_string_literal: true

require "test_helper"

module Rates
  class UsdHnlTest < ActiveSupport::TestCase
    setup { @pinned = UsdHnl.stub_rate; UsdHnl.stub_rate = nil }
    teardown { UsdHnl.stub_rate = @pinned; ENV.delete("HNL_PER_USD"); ENV.delete("BCH_API_KEY") }

    test "a manual override wins" do
      ENV["HNL_PER_USD"] = "25.90"
      info = UsdHnl.info
      assert_equal BigDecimal("25.90"), info.rate
      assert_equal "manual", info.source
    end

    test "prefers BCH when a key is configured, and stores the rate" do
      ENV["BCH_API_KEY"] = "k"
      stub_request(:get, %r{bchapi-am\.azure-api\.net/api/v1/indicadores/97/cifras}).with(headers: { "Ocp-Apim-Subscription-Key" => "k" })
        .to_return(status: 200, body: [ { "fecha" => "2026-09-11T00:00:00", "valor" => 26.1834 } ].to_json, headers: { "Content-Type" => "application/json" })

      info = UsdHnl.info
      assert_equal BigDecimal("26.1834"), info.rate
      assert_equal "bch", info.source
      assert_equal Date.new(2026, 9, 11), info.as_of
      assert_equal 1, ExchangeRate.count
      assert_equal "bch", ExchangeRate.last.source
    end

    test "falls back to the feed without a BCH key, then to the last stored rate, then to the constant" do
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.31 } }.to_json, headers: { "Content-Type" => "application/json" })
      assert_equal BigDecimal("26.31"), UsdHnl.current
      assert_equal "feed", ExchangeRate.last.source

      stub_request(:get, UsdHnl::FEED).to_return(status: 500, body: "")
      info = UsdHnl.info
      assert_equal BigDecimal("26.31"), info.rate, "keeps the stored rate when every source is down"
      assert_equal "feed", info.source

      ExchangeRate.delete_all
      assert_equal UsdHnl::FALLBACK, UsdHnl.current
    end

    # The rate was being fetched every few minutes because the refresh window
    # was a cache TTL, and a cache miss is invisible. The window is read from
    # the stored row now, so it holds across processes and deploys.
    test "inside the refresh window nothing is fetched at all" do
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.31 } }.to_json, headers: { "Content-Type" => "application/json" })
      assert_equal BigDecimal("26.31"), UsdHnl.current

      3.times { UsdHnl.info }
      assert_requested :get, UsdHnl::FEED, times: 1
    end

    test "past the window it fetches again" do
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.31 } }.to_json, headers: { "Content-Type" => "application/json" })
      UsdHnl.current
      ExchangeRate.usd_hnl.newest_first.first.update!(fetched_at: (UsdHnl::REFRESH_EVERY + 1.minute).ago)

      UsdHnl.info
      assert_requested :get, UsdHnl::FEED, times: 2
    end

    # The lempira moves a few times a month. A row per check buried the one
    # thing the history is for.
    test "confirming the same rate moves fetched_at instead of writing another row" do
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.31 } }.to_json, headers: { "Content-Type" => "application/json" })
      UsdHnl.current
      row = ExchangeRate.usd_hnl.newest_first.first
      row.update!(fetched_at: 2.days.ago)

      assert_no_difference("ExchangeRate.count") { UsdHnl.info }
      assert_operator row.reload.fetched_at, :>, 1.minute.ago
    end

    test "a rate that actually changed gets its own row" do
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.31 } }.to_json, headers: { "Content-Type" => "application/json" })
      UsdHnl.current
      ExchangeRate.usd_hnl.newest_first.first.update!(fetched_at: 2.days.ago)
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 27.02 } }.to_json, headers: { "Content-Type" => "application/json" })

      assert_difference("ExchangeRate.count", 1) { UsdHnl.info }
      assert_equal BigDecimal("27.02"), ExchangeRate.usd_hnl.newest_first.first.rate
    end

    test "ignores a BCH figure that cannot be a USD/HNL rate" do
      ENV["BCH_API_KEY"] = "k"
      stub_request(:get, %r{bchapi-am\.azure-api\.net}).to_return(status: 200, body: [ { "fecha" => "2026-09-11", "valor" => 4812.5 } ].to_json)
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.0 } }.to_json)
      assert_equal "feed", UsdHnl.info.source
    end
  end
end
