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

    test "ignores a BCH figure that cannot be a USD/HNL rate" do
      ENV["BCH_API_KEY"] = "k"
      stub_request(:get, %r{bchapi-am\.azure-api\.net}).to_return(status: 200, body: [ { "fecha" => "2026-09-11", "valor" => 4812.5 } ].to_json)
      stub_request(:get, UsdHnl::FEED).to_return(status: 200, body: { rates: { HNL: 26.0 } }.to_json)
      assert_equal "feed", UsdHnl.info.source
    end
  end
end
